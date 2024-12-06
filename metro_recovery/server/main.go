package main

import (
	"bufio"
	"context"
	"flag"
	"fmt"
	pb "go.etcd.io/etcd/v3/metro_recovery/proto"
	"go.etcd.io/etcd/v3/metro_recovery/walutil"
	"go.etcd.io/raft/v3/raftpb"
	"google.golang.org/grpc"
	"log"
	"net"
	"os"
	"strings"
	"sync"
	"time"
)

// WALServer is our implementation of the WALServiceServer interface
type WALServer struct {
	pb.UnimplementedWALServiceServer
	mu             sync.Mutex // Protect the entries map
	peers          []string   // List of peer addresses for recovery
	dataDir        string     // Path to the WAL directory
	myWAL          walutil.NodeWAL
	missingIndexes []uint64
	myLastIndex    uint64
	statsFile      string // Path to the stats file
}

// NewWALServer initializes the server with mock data and peers
func NewWALServer(peers []string, dataDir string, statsFile string) *WALServer {
	//log.Printf("Reading WAL from %s...", dataDir)
	myWAL, missingIndexes, err := walutil.ReadWALWithDetails(dataDir, true)
	if err != nil {
		log.Fatalf("Failed to read WAL: %v", err)
	}
	myLastIndex := myWAL.Entries[len(myWAL.Entries)-1].Index

	return &WALServer{
		peers:          peers,
		dataDir:        dataDir,
		myWAL:          myWAL,
		missingIndexes: missingIndexes,
		myLastIndex:    myLastIndex,
		statsFile:      statsFile,
	}
}

// GetMissingEntries handles gRPC requests for missing entries
func (s *WALServer) GetMissingEntries(ctx context.Context, req *pb.MissingEntriesRequest) (*pb.MissingEntriesResponse, error) {
	var responseEntries []*pb.Entry
	var missingIndex uint64 = 0
	numRequested := uint64(len(req.Indexes))
	for _, e := range s.myWAL.Entries {
		if missingIndex > s.myLastIndex || missingIndex >= numRequested {
			break
		}
		if e.Index == req.Indexes[missingIndex] {
			responseEntries = append(responseEntries, &pb.Entry{
				Index: e.Index,
				Term:  e.Term,
				Data:  e.Data,
			})
			missingIndex++
		}
	}
	//log.Printf("Returning %v missing entries.", len(responseEntries))
	return &pb.MissingEntriesResponse{Entries: responseEntries}, nil
}

// recoverWAL performs recovery by detecting missing entries, requesting them from peers, and merging them
func (s *WALServer) recoverWAL() {
	//log.Println("Starting recovery process...")

	if len(s.missingIndexes) == 0 {
		fmt.Println("No missing entries detected.")
		return
	}

	startTime := time.Now()

	// Request missing entries from peers
	var collectedEntries = make([]*pb.Entry, 0, len(s.missingIndexes))
	if len(s.peers) == 2 {
		collectedEntries = s.requestMissingEntriesForTwoPeers(s.missingIndexes)
	} else {
		collectedEntries = s.requestMissingEntries(s.missingIndexes)
	}

	// If no entries were collected, exit
	if len(collectedEntries) == 0 {
		fmt.Println("No missing entries could be retrieved from peers.")
		os.Exit(1) // Exit with code 1 to indicate failure
		return
	}

	fmt.Printf("Collected %d missing entries.\n", len(collectedEntries))

	// Merge collected entries into the WAL
	var missingRaftEntries []raftpb.Entry
	for _, e := range collectedEntries {
		missingRaftEntries = append(missingRaftEntries, raftpb.Entry{
			Index: e.Index,
			Term:  e.Term,
			Data:  e.Data,
		})
	}

	mergedWAL := walutil.MergeEntries(s.myWAL, missingRaftEntries)
	mergedDuration := time.Since(startTime)
	// Write the merged WAL back to the directory
	err := walutil.WriteWAL(s.dataDir, mergedWAL)
	if err != nil {
		log.Fatalf("Failed to write merged WAL: %v", err)
	}
	totalDuration := time.Since(startTime)
	log.Println("Recovery process completed.")
	s.writeStats(totalDuration, mergedDuration)
	os.Exit(0) // Exit with code 0 to indicate success
}

// writeStats writes recovery statistics to a specified file
func (s *WALServer) writeStats(totalDuration time.Duration, mergedDuration time.Duration) {
	if s.statsFile == "" {
		log.Println("No stats file provided. Skipping stats logging.")
		return
	}

	file, err := os.OpenFile(s.statsFile, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		log.Printf("Failed to open stats file: %v", err)
		return
	}
	defer file.Close()

	writer := bufio.NewWriter(file)
	_, err = writer.WriteString(fmt.Sprintf("totalDuration,mergeDuration,missingEntries\n%v,%v,%v",
		totalDuration.Milliseconds(), mergedDuration.Milliseconds(), len(s.missingIndexes)))
	if err != nil {
		log.Printf("Failed to write stats: %v", err)
		return
	}
	writer.Flush()
	log.Println("Recovery statistics written to file.")
}

// requestMissingEntries sends requests for missing entries to all peers
func (s *WALServer) requestMissingEntries(missingIndexes []uint64) []*pb.Entry {
	var collectedEntries []*pb.Entry
	var wg sync.WaitGroup
	mu := &sync.Mutex{} // Protect the collectedEntries slice

	for _, peer := range s.peers {
		wg.Add(1)
		go func(peer string) {
			defer wg.Done()
			conn, err := grpc.Dial(peer, grpc.WithInsecure())
			if err != nil {
				log.Printf("Failed to connect to peer %s: %v", peer, err)
				return
			}
			defer conn.Close()

			client := pb.NewWALServiceClient(conn)
			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()

			req := &pb.MissingEntriesRequest{Indexes: missingIndexes}
			res, err := client.GetMissingEntries(ctx, req)
			if err != nil {
				log.Printf("Failed to fetch entries from peer %s: %v", peer, err)
				return
			}

			mu.Lock()
			collectedEntries = append(collectedEntries, res.Entries...)
			mu.Unlock()
		}(peer)
	}
	wg.Wait()

	return collectedEntries
}

func (s *WALServer) requestMissingEntriesForTwoPeers(missingIndexes []uint64) []*pb.Entry {
	var collectedEntries []*pb.Entry
	var wg sync.WaitGroup
	mu := &sync.Mutex{} // Protect the collectedEntries slice

	if len(s.peers) != 2 {
		log.Println("Error: This function is optimized for exactly 2 peers.")
		return nil
	}

	// Split the missing indexes into two halves
	mid := len(missingIndexes) / 2
	firstHalf := missingIndexes[:mid]
	secondHalf := missingIndexes[mid:]

	peerRequests := []struct {
		peer    string
		indexes []uint64
	}{
		{s.peers[0], firstHalf},
		{s.peers[1], secondHalf},
	}

	maxMsgSize := 1024 * 1024 * 50 // 50 MB

	for _, request := range peerRequests {
		wg.Add(1)
		go func(peer string, indexes []uint64) {
			defer wg.Done()
			conn, err := grpc.Dial(
				peer,
				grpc.WithInsecure(),
				grpc.WithDefaultCallOptions(
					grpc.MaxCallRecvMsgSize(maxMsgSize), // Max incoming message size
					grpc.MaxCallSendMsgSize(maxMsgSize), // Max outgoing message size
				),
			)
			if err != nil {
				log.Printf("Failed to connect to peer %s: %v", peer, err)
				return
			}
			defer conn.Close()

			client := pb.NewWALServiceClient(conn)
			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()

			req := &pb.MissingEntriesRequest{Indexes: indexes}
			res, err := client.GetMissingEntries(ctx, req)
			if err != nil {
				log.Printf("Failed to fetch entries from peer %s: %v", peer, err)
				return
			}

			mu.Lock()
			collectedEntries = append(collectedEntries, res.Entries...)
			mu.Unlock()
		}(request.peer, request.indexes)
	}

	wg.Wait()
	return collectedEntries
}

// startGRPCServer starts the gRPC server
func startGRPCServer(port string, peers []string, dataDir string, statsFile string) {
	server := NewWALServer(peers, dataDir, statsFile)
	listener, err := net.Listen("tcp", ":"+port)
	if err != nil {
		log.Fatalf("Failed to listen on port %s: %v", port, err)
	}

	grpcServer := grpc.NewServer()
	pb.RegisterWALServiceServer(grpcServer, server)

	log.Printf("gRPC server running on port %s...", port)
	if err := grpcServer.Serve(listener); err != nil {
		log.Fatalf("Failed to serve: %v", err)
	}
}

// readPeersFromFile reads peer addresses from a file, excluding the current server's address.
func readPeersFromFile(filePath, selfAddress string) ([]string, error) {
	file, err := os.Open(filePath)
	if err != nil {
		return nil, fmt.Errorf("failed to open peers file: %w", err)
	}
	defer file.Close()

	var peers []string
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		peer := strings.TrimSpace(scanner.Text())
		if peer != "" && peer != selfAddress { // Exclude self
			peers = append(peers, peer)
		}
	}
	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("error reading peers file: %w", err)
	}
	log.Printf("Peers: %v", peers)
	return peers, nil
}

func main() {
	mode := flag.String("mode", "server", "Mode: 'server' to start the server, 'recover' to trigger recovery")
	port := flag.String("port", "50051", "Port for the gRPC server")
	dataDir := flag.String("data-dir", "./data", "Path to the etcd data directory (where WALs are stored)")
	peersFile := flag.String("peers-file", "", "Path to the file containing peer addresses (one per line)")
	ip := flag.String("ip", "", "IP address or hostname of the current server (required for peer filtering)")
	statsFile := flag.String("stats-file", "", "Path to the file to write recovery statistics")
	flag.Parse()

	if *ip == "" || *dataDir == "" || *peersFile == "" {
		log.Fatalf("Required fields missing: ip, data-dir, or peers-file")
	}

	selfAddress := fmt.Sprintf("%s:%s", *ip, *port)

	peers, err := readPeersFromFile(*peersFile, selfAddress)
	if err != nil {
		log.Fatalf("Failed to read peers: %v", err)
	}

	if *mode == "server" {
		startGRPCServer(*port, peers, *dataDir, *statsFile)
	} else if *mode == "recover" {
		server := NewWALServer(peers, *dataDir, *statsFile)
		server.recoverWAL()
	} else {
		fmt.Printf("Invalid mode: %s. Use 'server' or 'recover'.", *mode)
	}
}
