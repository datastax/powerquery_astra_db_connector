// Use this file to write queries to test your data connector
let
    result = astra_db_connector.Contents("4347e475-6515-4feb-a082-05dcb2721c5e", "us-east1")
    // result = astra_db_connector.Contents("4347e475-6515-4feb-a082-05dcb2721c5e", "us-east1", "pqdemo", "pqdata")

    // astraml_1
    // result = astra_db_connector.Contents("da3bf2ea-b408-44a0-a05e-b392d1c361b3", "us-east-1", "astraml_1", "orders")

in
    result
