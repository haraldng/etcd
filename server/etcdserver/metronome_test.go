package etcdserver_test

import (
	"fmt"
	"github.com/stretchr/testify/assert"
	"go.etcd.io/etcd/server/v3/etcdserver"
	//"gonum.org/v1/gonum/stat/combin"
	"testing"
)

// TestDistance checks the correctness of the distance function
func TestDistance(t *testing.T) {
	t1 := etcdserver.QuorumTuple{1, 2, 3}
	t2 := etcdserver.QuorumTuple{1, 5, 6}
	expected := 2

	result := etcdserver.Distance(t1, t2)
	if result != expected {
		t.Errorf("distance(%v, %v) = %d; want %d", t1, t2, result, expected)
	}
}

// TestMaximizeDistanceOrdering checks if the maximize distance function works as expected
func TestMaximizeDistanceOrdering(t *testing.T) {
	tuples := []etcdserver.QuorumTuple{
		{1, 2, 3},
		{3, 4, 5},
		{1, 2, 4},
		{4, 5, 6},
	}
	expected := []etcdserver.QuorumTuple{
		{1, 2, 3},
		{4, 5, 6},
		{1, 2, 4},
		{3, 4, 5},
	}

	orderedTuples := etcdserver.MaximizeDistanceOrdering(&tuples)
	if !equalQuorumTuples(orderedTuples, expected) {
		t.Errorf("maximizeDistanceOrdering() = %v; want %v", orderedTuples, expected)
	}
}

// TestNewMetronome checks the creation of a Metronome and ensures properties are correct
func TestNewMetronome(t *testing.T) {
	testCases := []int{3, 5, 7}

	for _, numNodes := range testCases {
		quorumSize := numNodes/2 + 1
		var allMetronomes []*etcdserver.Metronome

		for pid := 1; pid <= numNodes; pid++ {
			m := etcdserver.NewMetronome(pid, numNodes, quorumSize)
			allMetronomes = append(allMetronomes, m)

			if pid == 1 {
				t.Logf("N=%d: critical len: %d, total len: %d, ratio: %f", numNodes, m.CriticalLen, m.TotalLen, m.Ratio)
			}
			t.Log(m)
		}

		checkCriticalLen(t, allMetronomes)
	}
}

func TestMetronomeUsage(t *testing.T) {
	testCases := []int{3, 5, 7}
	pid := 1

	for _, numNodes := range testCases {
		quorumSize := numNodes/2 + 1
		m := etcdserver.NewMetronome(pid, numNodes, quorumSize)
		numOps := m.TotalLen * 3

		numToFlush := int(m.Ratio * float64(numOps))
		toFlush := make([]int, 0, numToFlush)
		fmt.Printf("%v\n", m.MyCriticalOrdering)
		for i := 0; i < numOps; i++ {
			metronomeIdx := i % m.TotalLen
			if m.MyCriticalOrdering[metronomeIdx] {
				fmt.Printf("Appending: i: %v, metronomeIdx: %v\n", i, metronomeIdx)
				toFlush = append(toFlush, i)
			}
		}
		assert.Equal(t, numToFlush, len(toFlush), "Number of critical ops should match")
	}
}

func countCriticalLen(m *etcdserver.Metronome) int {
	var criticalLen int
	for _, willFlush := range m.MyCriticalOrdering {
		if willFlush {
			criticalLen++
		}
	}
	return criticalLen
}

// Helper function to check if the critical lengths are the same and verify quorum assignments
func checkCriticalLen(t *testing.T, allMetronomes []*etcdserver.Metronome) {
	numNodes := len(allMetronomes)
	quorumSize := numNodes/2 + 1

	first_metro := allMetronomes[0]
	criticalLen := countCriticalLen(first_metro)
	totalLen := allMetronomes[0].TotalLen

	//fmt.Printf("criticalLen: %v\n", criticalLen)
	assert.Greater(t, totalLen, criticalLen, "Total length should be greater than critical length")
	assert.Greater(t, criticalLen, 0, "Critical length should be greater than 0")
	assert.Greater(t, totalLen, 0, "Total length should be greater than 0")

	// Ensure all metronomes have the same critical length
	for _, m := range allMetronomes {
		thisCriticalLen := countCriticalLen(m)
		if thisCriticalLen != criticalLen {
			t.Errorf("Expected critical length %d, but got %d", criticalLen, thisCriticalLen)
		}
		if m.TotalLen != totalLen {
			t.Errorf("Expected total length %d, but got %d", totalLen, m.TotalLen)
		}
	}

	allOrderings := make([][]int, 0, numNodes)
	for _, m := range allMetronomes {
		var orderingSlice []int
		for k, willFlush := range m.MyCriticalOrdering {
			if willFlush {
				orderingSlice = append(orderingSlice, k)
			}
		}
		allOrderings = append(allOrderings, orderingSlice)
	}

	fmt.Printf("allOrderings: %v\n", allOrderings)

	numOps := totalLen
	h := make(map[int]int, numOps)
	for i := 0; i < numOps; i++ {
		h[i] = 0
	}

	// Check column by column
	for column := 0; column < criticalLen; column++ {
		for _, ordering := range allOrderings {
			opID := ordering[column]
			h[opID]++
		}
	}

	// Ensure all ops were assigned across all nodes
	for _, count := range h {
		if count != quorumSize {
			t.Errorf("Expected quorumSize=%d assignments, but got %d", quorumSize, count)
		}
	}
}

// Helper function to compare two slices of etcdserver.QuorumTuples
func equalQuorumTuples(a, b []etcdserver.QuorumTuple) bool {
	if len(a) != len(b) {
		return false
	}

	for i := range a {
		if !etcdserver.Equal(a[i], b[i]) {
			return false
		}
	}
	return true
}
