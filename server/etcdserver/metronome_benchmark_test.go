package etcdserver

import (
	"os"
	"strings"
	"testing"
)

func BenchmarkDirectAppendToDiskWithFixedSizeBytes(b *testing.B) {
	// Initialize the larger array with X-byte strings
	const largerArraySize = 1000
	const valueSize = 16 // Replace with your desired byte size for each value (e.g., 16 bytes)

	// Create an array with values of 'valueSize' bytes
	largerArray := make([][]byte, largerArraySize)
	for i := 0; i < largerArraySize; i++ {
		// Create a byte slice of 'valueSize' bytes, consisting of repeated 'A' character
		largerArray[i] = []byte(strings.Repeat("A", valueSize))
	}

	// Create a temporary file to write the elements to disk (outside of benchmark loop)
	file, err := os.CreateTemp("", "direct_append_bytes_test")
	if err != nil {
		b.Fatalf("Failed to create temporary file: %v", err)
	}

	// Ensure file is cleaned up after benchmarking
	defer os.Remove(file.Name())

	b.ResetTimer() // Reset the timer to exclude setup time

	// Benchmark loop for direct append
	for i := 0; i < b.N; i++ {
		// Open the file in append mode
		f, err := os.OpenFile(file.Name(), os.O_APPEND|os.O_WRONLY, 0644)
		if err != nil {
			b.Fatalf("Failed to open file for appending: %v", err)
		}

		// Write the entire larger array to disk (append)
		for _, element := range largerArray {
			_, err := f.Write(element)
			if err != nil {
				b.Fatalf("Failed to write to file: %v", err)
			}
		}

		// Close the file after writing
		f.Close()
	}

	b.StopTimer() // Stop timer if there's any finalization needed after the benchmark
}
