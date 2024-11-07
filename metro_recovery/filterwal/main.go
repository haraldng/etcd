package main

import (
	"flag"
	"fmt"
	"log"

	"strconv"

	"go.etcd.io/etcd/v3/metro_recovery/walutil"
)

func main() {
	// Parse command-line arguments
	inputDir := flag.String("input", "", "Path to the input WAL directory")
	outputDir := flag.String("output", "", "Path to the output WAL directory")
	interval := flag.String("interval", "1", "Interval for filtering (keep every Nth entry)")
	flag.Parse()

	if *inputDir == "" || *outputDir == "" {
		log.Fatalf("Both --input and --output must be specified")
	}

	N, err := strconv.Atoi(*interval)
	if err != nil || N <= 0 {
		log.Fatalf("Invalid interval value: %s", *interval)
	}

	fmt.Printf("Filtering WAL: input=%s, output=%s, interval=%d\n", *inputDir, *outputDir, N)

	nodeWAL, err := walutil.ReadWAL(*inputDir)
	if err != nil {
		log.Fatalf("Failed to read WAL: %v", err)
	}

	filteredWAL := walutil.FilterWAL(nodeWAL, N)

	if err := walutil.WriteWAL(*outputDir, filteredWAL); err != nil {
		log.Fatalf("Failed to write filtered WAL: %v", err)
	}

	fmt.Println("Filtered WAL written successfully.")
}
