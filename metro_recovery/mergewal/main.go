package main

import (
	"fmt"
	"log"
	"os"
	"path/filepath"
	"sort"

	"go.etcd.io/etcd/v3/metro_recovery/walutil"
	"go.etcd.io/raft/v3/raftpb"
)

func main() {
	if len(os.Args) < 3 {
		fmt.Printf("Usage: %s <incompleteWAL> <providerWAL1> [<providerWAL2> ...]\n", filepath.Base(os.Args[0]))
		fmt.Println("Merges missing WAL entries from multiple provider WALs into the incomplete WAL.")
		os.Exit(1)
	}

	incompleteWALDir := os.Args[1]
	providerWALDirs := os.Args[2:]

	fmt.Printf("Merging WALs:\n- Incomplete WAL: %s\n- Provider WALs: %v\n", incompleteWALDir, providerWALDirs)

	// Read incomplete WAL with missing indexes
	incompleteWAL, missingIndexes, err := walutil.ReadAllWithMissingIndexes(incompleteWALDir)
	if err != nil {
		log.Fatalf("Failed to read incomplete WAL: %v", err)
	}

	if len(missingIndexes) == 0 {
		fmt.Println("No missing entries found in the incomplete WAL.")
		return
	}

	firstMissingIndex := missingIndexes[0]
	for i := 1; i < int(firstMissingIndex); i++ {
		missingIndexes = append(missingIndexes, uint64(i))
	}

	fmt.Printf("incompleteWAL: missing: %v\n", missingIndexes)

	// Prepare to collect missing entries from all providers
	providerEntriesMap := make(map[uint64]walutil.EntrySource)

	// Iterate through provider WALs
	for _, providerWALDir := range providerWALDirs {
		fmt.Printf("Processing provider WAL: %s\n", providerWALDir)

		// Read the provider WAL with its missing indexes
		providerWAL, providerMissingIndexes, err := walutil.ReadAllWithMissingIndexes(providerWALDir)
		if err != nil {
			fmt.Printf("Failed to read provider WAL %s: %v\n", providerWALDir, err)
			continue
		}

		// Map all entries from this provider for quick lookup
		for _, entry := range providerWAL.Entries {
			if _, exists := providerEntriesMap[entry.Index]; !exists {
				providerEntriesMap[entry.Index] = walutil.EntrySource{
					Entry: entry,
					Node:  providerWAL.NodeName,
				}
			}
		}

		// Log any missing entries in the provider WAL
		if len(providerMissingIndexes) > 0 {
			fmt.Printf("Provider WAL %s is missing %d entries: %v\n", providerWALDir, len(providerMissingIndexes), providerMissingIndexes)
		}
	}

	// Collect missing entries from providers
	var collectedEntries []walutil.EntrySource
	for _, idx := range missingIndexes {
		if source, ok := providerEntriesMap[idx]; ok {
			collectedEntries = append(collectedEntries, source)
		} else {
			fmt.Printf("No provider contains entry at index %d\n", idx)
		}
	}

	if len(collectedEntries) == 0 {
		fmt.Println("No missing entries could be retrieved from the provider WALs.")
		return
	}

	fmt.Printf("Found %d missing entries to merge.\n", len(collectedEntries))

	// Extract entries from collected sources
	var missingEntries []raftpb.Entry
	for _, source := range collectedEntries {
		missingEntries = append(missingEntries, source.Entry)
	}

	// Merge entries
	mergedWAL := mergeEntries(incompleteWAL, missingEntries)

	// Update HardState
	walutil.UpdateHardState(&mergedWAL)

	// Write merged WAL back to incomplete WAL directory
	fmt.Println("Writing merged WAL...")
	err = walutil.WriteWAL(incompleteWALDir, mergedWAL)
	if err != nil {
		log.Fatalf("Failed to write merged WAL: %v", err)
	}

	fmt.Println("Merged WAL written successfully.")
}

// mergeEntries merges missingEntries into incompleteWAL and returns a new NodeWAL.
func mergeEntries(incompleteWAL walutil.NodeWAL, missingEntries []raftpb.Entry) walutil.NodeWAL {
	// Combine existing entries with missing entries
	allEntries := append(incompleteWAL.Entries, missingEntries...)

	// Sort entries by Index
	sort.Slice(allEntries, func(i, j int) bool {
		return allEntries[i].Index < allEntries[j].Index
	})

	// Deduplicate entries
	deduplicatedEntries := deduplicateEntries(allEntries)

	// Return new NodeWAL with merged entries
	return walutil.NodeWAL{
		NodeName: incompleteWAL.NodeName,
		Metadata: incompleteWAL.Metadata,
		State:    incompleteWAL.State,
		Entries:  deduplicatedEntries,
	}
}

// deduplicateEntries removes duplicate entries based on their Index.
func deduplicateEntries(entries []raftpb.Entry) []raftpb.Entry {
	indexSeen := make(map[uint64]bool)
	var deduplicated []raftpb.Entry

	for _, entry := range entries {
		if !indexSeen[entry.Index] {
			deduplicated = append(deduplicated, entry)
			indexSeen[entry.Index] = true
		}
	}

	return deduplicated
}
