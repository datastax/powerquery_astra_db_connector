// This file contains your Data Connector logic
[Version = "0.1.0"]
section astra_db_connector;

// Settings
// set to empty string (no '?' to leave unspecified, i.e. server defaults)
tableUrlPageSizeSpecifier = ""; // "?page-size=2";

// library (navigation table)
// (see: https://learn.microsoft.com/en-us/power-query/helper-functions#tabletonavigationtable)
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
        keyspacesUrl = makeRestAPIUrl(databaseID, region, "schemas/keyspaces"),
        keyspacesTable = GetSinglePage(keyspacesUrl),
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
        tablesUrl = makeRestAPIUrl(databaseID, region, "schemas/keyspaces/" & keyspace & "/tables"),
        tablesTable = GetSinglePage(tablesUrl),
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
astra_db_connector.getDataForTable = (databaseID as text, region as text, keyspace as text, tableName as text) =>
    let
        tableUrl = makeRestAPIUrl(databaseID, region, "keyspaces/" & keyspace & "/" & tableName & "/rows" & tableUrlPageSizeSpecifier),
        dataTable = GetAllPagesByNextLink(tableUrl)
    in
        dataTable
;

// Pagination machinery
// (see: https://learn.microsoft.com/en-us/power-query/samples/trippin/5-paging/readme)

// The getNextPage function takes a single argument and is expected to return a nullable table
Table.GenerateByPage = (getNextPage as function) as table =>
    let
        listOfPages = List.Generate(
            () => getNextPage(null),            // get the first page of data
            (lastPage) => lastPage <> null,     // stop when the function returns null
            (lastPage) => getNextPage(lastPage) // pass the previous page to the next function call
        ),
        // concatenate the pages together
        tableOfPages = Table.FromList(listOfPages, Splitter.SplitByNothing(), {"Column1"}),
        firstRow = tableOfPages{0}?
    in
        // if we didn't get back any pages of data, return an empty table
        // otherwise set the table type based on the columns of the first page
        if (firstRow = null) then
            Table.FromRows({})
    // check for empty first table
        else if (Table.IsEmpty(firstRow[Column1])) then
            firstRow[Column1]
        else
            Value.ReplaceType(
                Table.ExpandTableColumn(tableOfPages, "Column1", Table.ColumnNames(firstRow[Column1])),
                Value.Type(firstRow[Column1])
            );

// Read all pages of data.
// Table.GenerateByPage will keep asking for more pages until we return null.
GetAllPagesByNextLink = (url as text) as table =>
    Table.GenerateByPage((previous) =>
        let
            // if previous is null, then this is our first page of data
            wasFirst = (previous = null), // boolean
            // if not first page, it's relevant to check if there is a next page or not
            nextPageState = Value.Metadata(previous)[nextPageState]?, // nullable
            page = if (wasFirst) then
                GetSinglePage(url)
            else (
                if (nextPageState <> null) then
                    GetSinglePage(url, nextPageState)
                else
                    null
            )
        in
            page
    );

// Request and parsing
GetSinglePage = (url as text, optional pageState as text) as table =>
    // if pageState is passed, it is appended to the URL at the last minute here
    let
        token = Extension.CurrentCredential()[Key],
        requestHeaders = [
            accept="application/json",
            #"X-Cassandra-Token"=token
        ],
        requestUrl = if (pageState <> null) then
            // there may be querystring params already, or not - handle this
            if(Text.Contains(url, "?")) then
                url & "&page-state=" & pageState
            else
                url & "?page-state=" & pageState
        else
            url,
        response = Web.Contents(requestUrl, [ Headers = requestHeaders ]),
        body = Json.Document(response),
        nextPageState = Record.FieldOrDefault(body, "pageState"),
        data = Table.FromRecords(body[data])
    in
        data meta [nextPageState = nextPageState]
;

[DataSource.Kind="astra_db_connector", Publish="astra_db_connector.Publish"]
// shared astra_db_connector.Contents = getWholeContents;
shared astra_db_connector.Contents = astra_db_connector.getDataForTable;

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
