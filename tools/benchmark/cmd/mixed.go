package cmd

import (
	"context"
	"encoding/binary"
	"fmt"
	"github.com/cheggaaa/pb/v3"
	"github.com/spf13/cobra"
	v3 "go.etcd.io/etcd/client/v3"
	"go.etcd.io/etcd/pkg/v3/report"
	"golang.org/x/time/rate"
	"math"
	"math/rand"
	"os"
	"path/filepath"
	"time"
)

var mixedCmd = &cobra.Command{
	Use:   "mixed",
	Short: "Benchmark mixed GET and PUT operations",
	Run:   mixedFunc,
}

type opType string

const (
	readOp  opType = "GET"
	writeOp opType = "PUT"
)

type labeledOp struct {
	op  v3.Op
	typ opType
}

var (
	mixedTotal       int
	mixedRate        int
	mixedKeySize     int
	mixedValSize     int
	mixedKeySpace    int
	mixedSequential  bool
	mixedReadPercent int
	preloadedKeys    []string
	outputDir        string
)

func init() {
	RootCmd.AddCommand(mixedCmd)

	mixedCmd.Flags().StringVar(&outputDir, "output-dir", ".", "Directory to store benchmark reports")
	mixedCmd.Flags().IntVar(&mixedTotal, "total", 10000, "Total number of operations (GET + PUT)")
	mixedCmd.Flags().IntVar(&mixedRate, "rate", 0, "Max operations per second (0 is no limit)")
	mixedCmd.Flags().IntVar(&mixedKeySize, "key-size", 8, "Key size")
	mixedCmd.Flags().IntVar(&mixedValSize, "val-size", 256, "Value size")
	mixedCmd.Flags().IntVar(&mixedKeySpace, "key-space-size", 1000, "Key space size")
	mixedCmd.Flags().BoolVar(&mixedSequential, "sequential-keys", false, "Use sequential keys")
	mixedCmd.Flags().IntVar(&mixedReadPercent, "read-percent", 50, "Percentage of GET operations (rest will be PUT)")
}

func mixedFunc(cmd *cobra.Command, _ []string) {
	if mixedKeySpace <= 0 {
		fmt.Fprintf(os.Stderr, "invalid --key-space-size (%d)\n", mixedKeySpace)
		os.Exit(1)
	}
	if mixedRate == 0 {
		mixedRate = math.MaxInt32
	}

	// Ensure output directory exists
	if err := os.MkdirAll(outputDir, 0755); err != nil {
		fmt.Fprintf(os.Stderr, "Failed to create output directory %s: %v\n", outputDir, err)
		os.Exit(1)
	}

	preloadEtcd(totalClients, totalConns) // Pass clients used for benchmarking

	clients := mustCreateClients(totalClients, totalConns)

	if mixedRate == 0 {
		mixedRate = math.MaxInt32
	}
	limit := rate.NewLimiter(rate.Limit(mixedRate), 1)

	bar = pb.New(mixedTotal)
	bar.Start()

	getReport := newReport()
	putReport := newReport()
	requests := make(chan labeledOp, totalClients)

	for i := range clients {
		wg.Add(1)
		go func(c *v3.Client) {
			defer wg.Done()
			for lo := range requests {
				limit.Wait(context.Background())

				st := time.Now()
				_, err := c.Do(context.Background(), lo.op)
				res := report.Result{Err: err, Start: st, End: time.Now()}
				switch lo.typ {
				case readOp:
					getReport.Results() <- res
				case writeOp:
					putReport.Results() <- res
				}
				bar.Increment()
			}
		}(clients[i])
	}

	go func() {
		for i := 0; i < mixedTotal; i++ {
			keyBytes := make([]byte, mixedKeySize)
			if mixedSequential {
				binary.PutVarint(keyBytes, int64(i%mixedKeySpace))
			} else {
				binary.PutVarint(keyBytes, int64(rand.Intn(mixedKeySpace)))
			}
			key := string(keyBytes)

			if rand.Intn(100) < mixedReadPercent {
				requests <- labeledOp{op: v3.OpGet(key), typ: readOp}
			} else {
				val := string(mustRandBytes(mixedValSize))
				requests <- labeledOp{op: v3.OpPut(key, val), typ: writeOp}
			}
		}
		close(requests)
	}()

	getRc := getReport.Run()
	putRc := putReport.Run()

	wg.Wait()
	close(getReport.Results())
	close(putReport.Results())
	bar.Finish()

	// ✅ Save GET report
	getFile := filepath.Join(outputDir, "get.txt")
	if err := writeReportToFile(<-getRc, getFile); err != nil {
		fmt.Fprintf(os.Stderr, "Failed to write GET report: %v\n", err)
	} else {
		fmt.Println("✅ GET report saved to ", getFile)
	}

	// ✅ Save PUT report
	putFile := filepath.Join(outputDir, "put.txt")
	if err := writeReportToFile(<-putRc, putFile); err != nil {
		fmt.Fprintf(os.Stderr, "Failed to write PUT report: %v\n", err)
	} else {
		fmt.Println("✅ PUT report saved to ", putFile)
	}
}

func preloadEtcd(totalClients uint, totalConns uint) {
	limit := rate.NewLimiter(rate.Limit(mixedRate), 1)
	clients := mustCreateClients(totalClients, totalConns)
	defer func() {
		for _, client := range clients {
			client.Close()
		}
	}()

	requests := make(chan labeledOp, totalClients)
	preloadReport := newReport()
	rc := preloadReport.Run()

	bar := pb.New(mixedKeySpace)
	bar.Start()

	for i := range clients {
		wg.Add(1)
		go func(c *v3.Client) {
			defer wg.Done()
			for lo := range requests {
				limit.Wait(context.Background())
				st := time.Now()
				_, err := c.Do(context.Background(), lo.op)
				preloadReport.Results() <- report.Result{Err: err, Start: st, End: time.Now()}
				bar.Increment()
			}
		}(clients[i])
	}

	go func() {
		for i := 0; i < mixedKeySpace; i++ {
			keyBytes := make([]byte, mixedKeySize)
			if mixedSequential {
				binary.PutVarint(keyBytes, int64(i%mixedKeySpace))
			} else {
				binary.PutVarint(keyBytes, int64(rand.Intn(mixedKeySpace)))
			}
			key := string(keyBytes)
			val := string(mustRandBytes(mixedValSize))
			requests <- labeledOp{op: v3.OpPut(key, val), typ: writeOp}
		}
		close(requests)
	}()

	wg.Wait()
	bar.Finish()
	close(preloadReport.Results())

	// ✅ Save preload report to file
	loadFile := filepath.Join(outputDir, "load.txt")
	if err := writeReportToFile(<-rc, loadFile); err != nil {
		fmt.Fprintf(os.Stderr, "Failed to write preload report: %v\n", err)
	} else {
		fmt.Println("✅ Preload report saved to ", loadFile)
	}

	fmt.Println("Pre-loading completed. Sleeping for 10 seconds before starting benchmark...")
	time.Sleep(10 * time.Second)
}

func writeReportToFile(summary string, filename string) error {
	fmt.Println(filename, summary)
	f, err := os.Create(filename)
	if err != nil {
		return err
	}
	defer f.Close()

	_, err = f.WriteString(summary)
	return err
}
