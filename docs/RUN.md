
time curl -sS --max-time 10 http://127.0.0.1:8899 \
    -H 'content-type: application/json' \
    --data '{
      "jsonrpc":"2.0",
      "id":2,
      "method":"getAccountInfo",
      "params":[
        "3gS3zwNsJWPmzjRrSTEd9TGevFwwj3xm2wnAeqBMDn5A",
        {
          "encoding":"base64",
          "commitment":"confirmed"
        }
      ]
    }' | jq '{error, found:(.result.value != null), slot:.result.context.slot}'


time curl -sS --max-time 10 http://127.0.0.1:8899     -H 'content-type: application/json'     --data '{
      "jsonrpc":"2.0",
      "id":2,
      "method":"getAccountInfo",
      "params":[
        "3gS3zwNsJWPmzjRrSTEd9TGevFwwj3xm2wnAeqBMDn5A",
        {
          "encoding":"base64",
          "commitment":"confirmed"
        }
      ]
    }' | jq '{error, found:(.result.value != null), slot:.result.context.slot}'

