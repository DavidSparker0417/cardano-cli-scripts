FUNCTION=$1
PARAM_1=$2
PARAM_2=$3
PARAM_3=$4

export CARDANO_NODE_SOCKET_PATH=~/cardano/node/node.socket
export LD_LIBRARY_PATH=/usr/local/lib
# CLI=~/cardano/node/bin/cardano-cli
CLI=cardano-cli

NET="--testnet-magic 1097911063"
WDIR=~/cardano/david/wallets
WALLET_DIR=~/cardano/david/wallets/david
MY_WALLET=$(cat $WALLET_DIR/payment.address)
PROTOCOL_FILE=~/cardano/node/protocol.json

################################################################################
############################ Getting public information ########################
################################################################################
GetCurrentProtocol() {
  echo ================== Getting Current Profile ==============
  $CLI query protocol-parameters $NET --out-file $PROTOCOL_FILE
}

UtxoGetFirst() {
  utxo=$($CLI query utxo $NET --address $MY_WALLET | grep lovelace | sed -n '1p')
  c_hash=$(echo $utxo | awk '{print $1}')
  c_txid=$(echo $utxo | awk '{print $2}')
  echo $c_hash#$c_txid
}

UtxoGet() {
  n=$1p
  utxo=$($CLI query utxo $NET --address $MY_WALLET | grep lovelace | sed -n $n)
  c_hash=$(echo $utxo | awk '{print $1}')
  c_txid=$(echo $utxo | awk '{print $2}')
  echo $c_hash#$c_txid
}

CalcDatumHash() {
  datum=$1
  $CLI transaction hash-script-data --script-data-value $datum
}

GetAdaFromPlutus() {
  plutus=$1
  datum=$2

  # get address from plutus script
  scriptAddr=$(ScriptGetAddr $plutus)
  
  # calculate datum hash
  dhash=$(CalcDatumHash $datum)

  # get utxo of script having datum hash
  availUtxos=$($CLI query utxo $NET --address $scriptAddr | grep $dhash)
  IFS=$'\n'
  availUtxoArray=( ${availUtxos} )
  for utxo in ${availUtxoArray[@]}
    do 
      # echo $utxo
      txHash=$(echo $utxo | awk '{print $1}')
      txId=$(echo $utxo | awk '{print $2}')
      lovelace=$(echo $utxo | awk '{print $3}')
      asset=$(echo $utxo | awk '{print $6}')
      if [[ $asset == "TxOutDatumHash" ]]; then
        echo "Getting lovelace($lovelace) from $txHash#$txId"
      UnlockFundsFromScript $txHash#$txId $plutus $datum
      # elif [[ $asset == "TxOutDatumNone" ]]; then
      #   echo "Getting lovelace($lovelace) from $txHash#$txId"
      #   UnlockFundsFromScript $txHash#$txId $plutus $datum
      fi
  done
}

NFT_CreateDefaultPolicy() {
  POLICY_FILE=$1
  rm -f $POLICY_FILE
  echo "{" >> $POLICY_FILE
  echo "  \"keyHash\": \"$($CLI address key-hash --payment-verification-key-file $WALLET_DIR/payment.vkey)\"," >> $POLICY_FILE
  echo "  \"type\": \"sig\"" >> $POLICY_FILE 
  echo "}" >> $POLICY_FILE 

  $CLI transaction policyid --script-file $POLICY_FILE > policy.id
}

NFT_CreateMetadata() {
  realtokenname=$1
  ipfs_hash=$2

  rm -f metadata.json
  echo "{" >> metadata.json
  echo "  \"721\": {" >> metadata.json 
  echo "    \"$(cat policy.id)\": {" >> metadata.json 
  echo "      \"$(echo $realtokenname)\": {" >> metadata.json
  echo "        \"description\": \"This is my first NFT thanks to the Cardano foundation\"," >> metadata.json
  echo "        \"name\": \"Cardano foundation NFT guide token\"," >> metadata.json
  echo "        \"id\": \"1\"," >> metadata.json
  echo "        \"image\": \"ipfs://$(echo $ipfs_hash)\"" >> metadata.json
  echo "      }" >> metadata.json
  echo "    }" >> metadata.json 
  echo "  }" >> metadata.json 
  echo "}" >> metadata.json
}

TrFeeCalc() {
  bodyFile=$1
  feeComment=$($CLI transaction calculate-min-fee \
    --tx-body-file $bodyFile \
    --tx-in-count 1 \
    --tx-out-count 1 \
    --witness-count 2 \
    --testnet-magic 1 \
    --protocol-params-file $PROTOCOL_FILE)
  echo $(echo $feeComment | awk '{print $1}')
}

################################################################################
##################################### Key related    ###########################
################################################################################
keyGenerate() {
  name=$1
  dir=$WDIR/$name
  mkdir -p $dir
  $CLI  address key-gen \
    --verification-key-file $dir/payment.vkey \
    --signing-key-file $dir/payment.skey
  $CLI stake-address key-gen \
    --verification-key-file $dir/stake.vkey \
    --signing-key-file $dir/stake.skey
  cardano-cli address build \
    --payment-verification-key-file $dir/payment.vkey \
    --stake-verification-key-file $dir/stake.vkey \
    --out-file $dir/payment.addr \
    $NET
}

keyHash() {
  name=$1
  $CLI address key-hash --payment-verification-key-file $WDIR/$name/payment.vkey
}

################################################################################
############################ Script related          ###########################
################################################################################
scriptAddrBuild() {
  plutusFile=$1
  $CLI address build \
    --payment-script-file $plutusFile \
    $NET
}

scriptGetDatumHashByFile() {
  jsonFile=$1
  $CLI transaction \
    hash-script-data \
    --script-data-file $jsonFile
}

################################################################################
############################ Main Interface Commands ###########################
################################################################################
UnlockFundsFromScript() {
  TX_SCRIPT=$1
  FILE=$2
  DATUM_VALUE=$3

  callateralUtxo=$(UtxoGetFirst)
  $CLI transaction build \
    --babbage-era \
    $NET \
    --tx-in ${TX_SCRIPT} \
    --tx-in-script-file ${FILE} \
    --tx-in-datum-value $DATUM_VALUE \
    --tx-in-redeemer-value $DATUM_VALUE \
    --tx-in-collateral $(UtxoGetFirst) \
    --change-address $MY_WALLET \
    --protocol-params-file /david/cardano/protocol.json \
    --out-file tx.raw 

  return
  $CLI transaction sign \
    --tx-body-file tx.raw \
    --signing-key-file $WALLET_DIR/payment.skey \
    $NET --out-file tx.signed
  
  rm -f tx.raw
  
  $CLI transaction submit \
    $NET \
    --tx-file tx.signed
  rm -f tx.signed
}

CreateNft() {
  realName=$1
  ipfs_hash=$1
  # QmbH8USyX9z7bus48qg7MDaX52Ktc2KKmQ3F6uReLqyjLc

  tokenname=$(echo -n $realName | xxd -b -ps -c 80 | tr -d '\n')
  
  # make directory
  cd ../nfts
  mkdir -p $realName
  # create script & id & metadata
  echo ================== Creating script and metadata ==============
  cd $realName
  NFT_CreateDefaultPolicy policy.script
  NFT_CreateMetadata $realName QmbH8USyX9z7bus48qg7MDaX52Ktc2KKmQ3F6uReLqyjLc
  # build transaction
  echo ================== Building Transaction ==============
  txIn=$(UtxoGetFirst)
  lovelace=$($CLI query utxo --tx-in $txIn $NET | grep lovelace | awk '{print $3}')
  value="1 $(cat policy.id).$tokenname"
  defOut=1142150
  $CLI transaction build-raw \
    --fee 0 \
    --babbage-era \
    --tx-in $txIn \
    --tx-out $MY_WALLET+$lovelace+"$value" \
    --mint="$value" \
    --minting-script-file policy.script \
    --metadata-json-file metadata.json  \
    --out-file matx.raw
  fee=$(TrFeeCalc matx.raw)
  totalNeededOut=$(($defOut + $fee))
  txInParam=" --tx-in $txIn"
  if (( $lovelace < $totalNeededOut )); then
    tx=$(UtxoGet 2)
    txInParam="$txInParam --tx-in $tx"
  fi
  echo $txInParam
  $CLI transaction build \
    $NET \
    --babbage-era \
    $txInParam \
    --tx-out $MY_WALLET+$defOut+"$value" \
    --change-address $MY_WALLET \
    --mint="$value" \
    --minting-script-file policy.script \
    --metadata-json-file metadata.json  \
    --witness-override 2 \
    --out-file matx.raw
  # Sign and submit transaction
  echo ================== Sign and submitting transaction ==============
  $CLI transaction sign  \
    --signing-key-file $WALLET_DIR/payment.skey  \
    --mainnet --tx-body-file matx.raw  \
    --out-file matx.signed
  rm -f matx.raw
  $CLI transaction submit \
    --tx-file matx.signed \
    $NET
  rm -f matx.signed
}

if [[ $FUNCTION == "" ]]; then
  echo "Invalid command!"
  # Build
  # sleep 3
  # Sign
  # sleep 3
  # Submit    
else
    $FUNCTION $PARAM_1 $PARAM_2 $PARAM_3
fi
