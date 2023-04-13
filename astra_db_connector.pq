// This file contains your Data Connector logic
[Version = "0.1.0"]
section astra_db_connector;

// Url path handling
makeRestAPIUrl = (databaseID as text, region as text, optional subpath as text) as text =>
    let
        fullUrl = "https://" & databaseID & "-" & region & ".apps.astra.datastax.com/api/rest/v2/" & (if (subpath=null) then "" else subpath)
    in
        fullUrl
;

// Schema handling
getWholeContents = (databaseID as text, region as text) =>
    let
        token = Extension.CurrentCredential()[Key],
        keyspacesUrl = makeRestAPIUrl(databaseID, region, "schemas/keyspaces"),
        keyspacesTable = GetPage(keyspacesUrl, token),
        removed = Table.RemoveColumns(keyspacesTable,{"datacenters"}),
        renamed = Table.RenameColumns(removed,{{"name", "Keyspace"}})
    in
        renamed
;

// Request and parsing
GetPage = (url as text, astraToken as text) as table =>
    let
        requestHeaders = [
            accept="application/json",
            #"X-Cassandra-Token"=astraToken
        ],
        response = Web.Contents(url, [ Headers = requestHeaders ]),        
        body = Json.Document(response),
        data = Table.FromRecords(body[data])
    in
        data;

[DataSource.Kind="astra_db_connector", Publish="astra_db_connector.Publish"]
shared astra_db_connector.Contents = getWholeContents;
// shared astra_db_connector.Contents = (optional message as text) =>
//     let
//         _message = if (message <> null) then message else "(no message)",
//         a = "Hello from astra_db_connector: " & _message
//     in
//         a;

// Data Source Kind description
astra_db_connector = [
    Authentication = [
        Key = [
            KeyLabel="Token"
        ]
    ]
];

// Data Source UI publishing description
astra_db_connector.Publish = [
    Beta = true,
    Category = "Other",
    ButtonText = { Extension.LoadString("ButtonTitle"), Extension.LoadString("ButtonHelp") },
    LearnMoreUrl = "https://powerbi.microsoft.com/",
    SourceImage = astra_db_connector.Icons,
    SourceTypeImage = astra_db_connector.Icons
];

astra_db_connector.Icons = [
    Icon16 = { Extension.Contents("astra_db_connector16.png"), Extension.Contents("astra_db_connector20.png"), Extension.Contents("astra_db_connector24.png"), Extension.Contents("astra_db_connector32.png") },
    Icon32 = { Extension.Contents("astra_db_connector32.png"), Extension.Contents("astra_db_connector40.png"), Extension.Contents("astra_db_connector48.png"), Extension.Contents("astra_db_connector64.png") }
];
