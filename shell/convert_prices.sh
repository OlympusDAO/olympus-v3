source .env

# Loop through price array
for i in "${PRICES[@]}"
do
    cast --to-uint256 $i
done