// This file contains your Data Connector logic
[Version = "0.1.0"]
section astra_db_connector;

// library (navigation table)
Table.ToNavigationTable = (
    table as table,
    keyColumns as list,
    nameColumn as text,
    dataColumn as text,
    itemKindColumn as text,
    itemNameColumn as text,
    isLeafColumn as text
) as table =>
    let
        tableType = Value.Type(table),
        newTableType = Type.AddTableKey(tableType, keyColumns, true) meta 
        [
            NavigationTable.NameColumn = nameColumn, 
            NavigationTable.DataColumn = dataColumn,
            NavigationTable.ItemKindColumn = itemKindColumn, 
            Preview.DelayColumn = itemNameColumn, 
            NavigationTable.IsLeafColumn = isLeafColumn
        ],
        navigationTable = Value.ReplaceType(table, newTableType)
    in
        navigationTable;

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
        // in the output from REST API, certain entries only have "name": system keyspaces, we discard them.
        cleanedKeyspacesTable = Table.RemoveRowsWithErrors(keyspacesTable, {"datacenters"}),
        usableKeyspacesTable = Table.SelectRows(cleanedKeyspacesTable, each "datacenters" <> null),
        removed = Table.RemoveColumns(usableKeyspacesTable,{"datacenters"}),
        renamed = Table.RenameColumns(removed,{{"name", "Keyspace"}}),
        // Add Data as a calculated column
        withData = Table.AddColumn(renamed, "Data", each astra_db_connector.getTablesForKeyspace(databaseID, region, [Keyspace])),
        // Add ItemKind and ItemName as fixed text values
        withItemKind = Table.AddColumn(withData, "ItemKind", each "View", type text),
        withItemName = Table.AddColumn(withItemKind, "ItemName", each "Table", type text),
        // Indicate that the node should not be expandable
        withIsLeaf = Table.AddColumn(withItemName, "IsLeaf", each false, type logical),
        // Generate the nav table
        navTable = Table.ToNavigationTable(withIsLeaf, {"Keyspace"}, "Keyspace", "Data", "ItemKind", "ItemName", "IsLeaf")
    in
        navTable
;

astra_db_connector.getTablesForKeyspace = (databaseID as text, region as text, keyspace as text) =>
    let
        token = Extension.CurrentCredential()[Key],
        tablesUrl = makeRestAPIUrl(databaseID, region, "schemas/keyspaces/" & keyspace & "/tables"),
        tablesTable = GetPage(tablesUrl, token),
        removed = Table.SelectColumns(tablesTable, {"name"}),
        renamed = Table.RenameColumns(removed,{{"name", "Table"}}),
        // Add Data as a calculated column
        withData = Table.AddColumn(renamed, "Data", each astra_db_connector.getDataForTable(databaseID, region, keyspace, [Table])),
        // Add ItemKind and ItemName as fixed text values
        withItemKind = Table.AddColumn(withData, "ItemKind", each "Table", type text),
        withItemName = Table.AddColumn(withItemKind, "ItemName", each "Table", type text),
        // Indicate that the node should not be expandable
        withIsLeaf = Table.AddColumn(withItemName, "IsLeaf", each true, type logical),
        // Generate the nav table
        navTable = Table.ToNavigationTable(withIsLeaf, {"Table"}, "Table", "Data", "ItemKind", "ItemName", "IsLeaf")
    in
        navTable
;

// data retrieval from a table
testData = {
    "Fake",
    "Test",
    "Hardcoded",
    "Data"
};
astra_db_connector.getDataForTable = (databaseID as text, region as text, keyspace as text, tableName as text) =>
    let
        token = Extension.CurrentCredential()[Key],
        tableUrl = makeRestAPIUrl(databaseID, region, "keyspaces/" & keyspace & "/" & tableName & "/rows"),
        dataTable = GetPage(tableUrl, token)
    in
        dataTable
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
