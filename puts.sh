#!/bin/bash

# Ensure the required number of arguments is passed
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <N>"
    exit 1
fi

# Number of requests
N=$1

# Define the alphabet
ALPHABET=(a b c d e f g h i j k l m n o p q r s t u v w x y z)

# Loop to perform put operations
for ((i = 1; i <= N; i++)); do
    # Get the corresponding key from ALPHABET, wrapping around if N > 26
    KEY=${ALPHABET[$(( (i - 1) % 26 ))]}

    # Execute etcdctl put command
    bin/etcdctl put "$KEY" "$i"
    echo "Put key: $KEY, value: $i"
done

echo "Done. $N keys written to etcd."
