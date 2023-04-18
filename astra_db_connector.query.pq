// Use this file to write queries to test your data connector
let
    // result = astra_db_connector.Contents("4347e475-6515-4feb-a082-05dcb2721c5e", "us-east1")
    result = astra_db_connector.Contents("4347e475-6515-4feb-a082-05dcb2721c5e", "us-east1", "pqdemo", "pqdata")
in
    Table.Schema(result)
    // result


