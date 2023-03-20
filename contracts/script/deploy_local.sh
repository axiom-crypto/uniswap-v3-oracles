LOCAL_RPC_URL="http://localhost:8545"
CONTRACT_NAME="UniswapV3Oracle"
SCRIPT_NAME=${CONTRACT_NAME}Script
forge script "script/$CONTRACT_NAME.s.sol:$SCRIPT_NAME" --rpc-url $LOCAL_RPC_URL --broadcast -vvvv
