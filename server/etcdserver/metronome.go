package etcdserver

import (
	//"fmt"
	"math"
	"sort"
)

// NodeId is a type alias for node identifiers

// Metronome struct to hold state
type Metronome struct {
	// Id of this node
	Pid                int
	MyCriticalOrdering map[int]bool
	TotalLen           int
}

// QuorumTuple is a type alias for a slice of NodeIds
type QuorumTuple []int

// MaximizeDistanceOrdering reorders quorums to maximize the Distance between consecutive ones
func MaximizeDistanceOrdering(tuples *[]QuorumTuple) []QuorumTuple {
	orderedTuples := []QuorumTuple{(*tuples)[0]}
	*tuples = (*tuples)[1:] // Remove first element

	for len(*tuples) > 0 {
		// Find quorums with no common node with the last one
		noRepeatTuples := []QuorumTuple{}
		for _, t := range *tuples {
			if len(intersect(orderedTuples[len(orderedTuples)-1], t)) == 0 {
				noRepeatTuples = append(noRepeatTuples, t)
			}
		}

		var nextTuple QuorumTuple
		if len(noRepeatTuples) > 0 {
			// Choose one with maximum distance
			sort.Slice(noRepeatTuples, func(i, j int) bool {
				return Distance(orderedTuples[len(orderedTuples)-1], noRepeatTuples[i]) > Distance(orderedTuples[len(orderedTuples)-1], noRepeatTuples[j])
			})
			nextTuple = noRepeatTuples[0]
		} else {
			// All quorums have common nodes, pick the one with max distance
			sort.Slice(*tuples, func(i, j int) bool {
				return Distance(orderedTuples[len(orderedTuples)-1], (*tuples)[i]) > Distance(orderedTuples[len(orderedTuples)-1], (*tuples)[j])
			})
			nextTuple = (*tuples)[0]
		}

		orderedTuples = append(orderedTuples, nextTuple)
		*tuples = removeTuple(*tuples, nextTuple)
	}
	return orderedTuples
}

// Distance calculates the Euclidean Distance between two quorum tuples
func Distance(t1, t2 QuorumTuple) int {
	if len(t1) != len(t2) {
		panic("Vectors must have the same dimension for distance calculation")
	}

	sumOfSquares := 0
	for i := range t1 {
		diff := int(t1[i]) - int(t2[i])
		sumOfSquares += diff * diff
	}

	return int(math.Sqrt(float64(sumOfSquares)))
}

// createOrderedQuorums generates quorum combinations and orders them
func createOrderedQuorums(numNodes, quorumSize int) []QuorumTuple {
	quorumCombos := combinations(1, numNodes, quorumSize)
	return MaximizeDistanceOrdering(&quorumCombos)
}

// getMyOrdering returns the ordering for the current node and the critical length
func getMyOrdering(myPid int, orderedQuorums []QuorumTuple) map[int]bool {
	ordering := make(map[int]bool)
	for entryId, q := range orderedQuorums {
		if contains(q, myPid) {
			ordering[entryId] = true
		}
	}
	return ordering
}

// Helper function to generate combinations
func combinations(start, end, quorumSize int) []QuorumTuple {
	result := []QuorumTuple{}
	comb := make([]int, quorumSize)
	var combine func(int, int)
	combine = func(start, depth int) {
		if depth == quorumSize {
			temp := make(QuorumTuple, quorumSize)
			copy(temp, comb)
			result = append(result, temp)
			return
		}
		for i := start; i <= end; i++ {
			comb[depth] = i
			combine(i+1, depth+1)
		}
	}
	combine(start, 0)
	return result
}

// Helper function to find the intersection of two QuorumTuples
func intersect(a, b QuorumTuple) QuorumTuple {
	set := make(map[int]bool)
	for _, v := range a {
		set[v] = true
	}

	var result QuorumTuple
	for _, v := range b {
		if set[v] {
			result = append(result, v)
		}
	}
	return result
}

// Helper function to check if a QuorumTuple contains a specific NodeId
func contains(q QuorumTuple, pid int) bool {
	for _, id := range q {
		if id == pid {
			return true
		}
	}
	return false
}

// Helper function to remove a specific QuorumTuple from a slice of QuorumTuples
func removeTuple(tuples []QuorumTuple, tuple QuorumTuple) []QuorumTuple {
	for i, t := range tuples {
		if Equal(t, tuple) {
			return append(tuples[:i], tuples[i+1:]...)
		}
	}
	return tuples
}

// Helper function to compare two QuorumTuples
func Equal(t1, t2 QuorumTuple) bool {
	if len(t1) != len(t2) {
		return false
	}
	for i := range t1 {
		if t1[i] != t2[i] {
			return false
		}
	}
	return true
}

// NewMetronome Metronome factory function to create a new Metronome instance
func NewMetronome(pid int, numNodes, quorumSize int) *Metronome {
	orderedQuorums := createOrderedQuorums(numNodes, quorumSize)
	ordering := getMyOrdering(pid, orderedQuorums)
	return &Metronome{
		Pid:                pid,
		MyCriticalOrdering: ordering,
		TotalLen:           len(orderedQuorums),
	}
}
