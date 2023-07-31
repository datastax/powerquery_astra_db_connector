// This file contains your Data Connector logic
[Version = "0.1.2"]
section #"AstraDB";

/*
    Library function to make a "navigation table"
    (see: https://learn.microsoft.com/en-us/power-query/helper-functions#tabletonavigationtable)
    A regular table is equipped with certain properties so that e.g. in PowerBI it looks like
    a list of choosable entries (e.g. choose-keyspace, choose-table).
    This code comes straight from the M documentation.
*/
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
        navigationTable
;

/*
    Library function to enforce a schema on a table.
    See https://learn.microsoft.com/en-us/power-query/samples/trippin/6-schema/readme
*/
EnforceSchema.Strict = 1;               // Add any missing columns, remove extra columns, set table type
EnforceSchema.IgnoreExtraColumns = 2;   // Add missing columns, do not remove extra columns
EnforceSchema.IgnoreMissingColumns = 3; // Do not add or remove columns
SchemaTransformTable = (table as table, schema as table, optional enforceSchema as number) as table =>
    let
        // Default to EnforceSchema.Strict
        _enforceSchema = if (enforceSchema <> null) then enforceSchema else EnforceSchema.Strict,

        // Applies type transforms to a given table
        EnforceTypes = (table as table, schema as table) as table =>
            let
                map = (t) => if Type.Is(t, type list) or Type.Is(t, type record) or t = type any then null else t,
                mapped = Table.TransformColumns(schema, {"Type", map}),
                omitted = Table.SelectRows(mapped, each [Type] <> null),
                existingColumns = Table.ColumnNames(table),
                removeMissing = Table.SelectRows(omitted, each List.Contains(existingColumns, [Name])),
                primitiveTransforms = Table.ToRows(removeMissing),
                changedPrimitives = Table.TransformColumnTypes(table, primitiveTransforms)
            in
                changedPrimitives,

        // Returns the table type for a given schema
        SchemaToTableType = (schema as table) as type =>
            let
                toList = List.Transform(schema[Type], (t) => [Type=t, Optional=false]),
                toRecord = Record.FromList(toList, schema[Name]),
                toType = Type.ForRecord(toRecord, false)
            in
                type table (toType),

        // Determine if we have extra/missing columns.
        // The enforceSchema parameter determines what we do about them.
        schemaNames = schema[Name],
        foundNames = Table.ColumnNames(table),
        addNames = List.RemoveItems(schemaNames, foundNames),
        extraNames = List.RemoveItems(foundNames, schemaNames),
        tmp = Text.NewGuid(),
        added = Table.AddColumn(table, tmp, each []),
        expanded = Table.ExpandRecordColumn(added, tmp, addNames),
        result = if List.IsEmpty(addNames) then table else expanded,
        fullList =
            if (_enforceSchema = EnforceSchema.Strict) then
                schemaNames
            else if (_enforceSchema = EnforceSchema.IgnoreMissingColumns) then
                foundNames
            else
                schemaNames & extraNames,

        // Select the final list of columns.
        // These will be ordered according to the schema table.
        reordered = Table.SelectColumns(result, fullList, MissingField.Ignore),
        enforcedTypes = EnforceTypes(reordered, schema),
        withType = if (_enforceSchema = EnforceSchema.Strict) then Value.ReplaceType(enforcedTypes, SchemaToTableType(schema)) else enforcedTypes
    in
        withType;

// Settings
// Set to empty string for server defaults, or something like "?page-size=2" (incl. the "?")
tableUrlPageSizeSpecifier = ""; // "?page-size=2";
// Timeout for all HTTP requests (days, hours, minutes, seconds)
httpTimeout = #duration(0, 0, 0, 20);
// Astra DB system keyspaces to hide (i.e. those not accessible with a DB-scoped token)
hiddenAstraKeyspaces = {
    "data_endpoint_auth",
    "system_auth",
    "datastax_sla",
    "system",
    "system_schema",
    "system_traces"
};

// REST API Handling - url/path construction
makeRestAPIUrl = (databaseID as text, region as text, optional subpath as text) as text =>
    let
        fullUrl = "https://" & databaseID & "-" & region & ".apps.astra.datastax.com/api/rest/v2/" & (if (subpath=null) then "" else subpath)
    in
        fullUrl
;

// SCHEMA handling - get all keyspaces
// This is the "schema-based" call, requiring an across-DB token. Deprecated
AstraDB.getKeyspacesSchemaCall = (databaseID as text, region as text) =>
    let
        keyspacesUrl = makeRestAPIUrl(databaseID, region, "schemas/keyspaces"),
        keyspacesTable = getSinglePage(keyspacesUrl),
        // in the output from REST API, certain entries should be hidden
        // Actually it seems that only the 'system' keyspace will be later unreadable. However we align with the read-table approach
        // ... but for some reason we also have to take care of some records not having 'datacenters'. Let's get rid of them (system keyspaces anyway)
        cleanedKeyspacesTable = Table.RemoveRowsWithErrors(keyspacesTable, {"datacenters"}),
        usableKeyspacesTable = Table.SelectRows(cleanedKeyspacesTable, each not List.Contains(hiddenAstraKeyspaces, [name])),
        removed = Table.SelectColumns(usableKeyspacesTable,{"name"}),
        removedSorted = Table.Sort(removed, {"name"}),
        renamed = Table.RenameColumns(removedSorted, {{"name", "Keyspace"}}),
        // Add Data as a calculated column
        withData = Table.AddColumn(renamed, "Data", each AstraDB.getTablesForKeyspace(databaseID, region, [Keyspace])),
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

// SCHEMA handling - get all keyspaces
// This is the "system-table-based" call, requiring a regular DB-scoped token. Preferrable
AstraDB.getKeyspacesTableReadCall = (databaseID as text, region as text) =>
    let
        keyspacesUrl = makeRestAPIUrl(databaseID, region, "keyspaces/system_schema/keyspaces/rows"),
        keyspacesTable = Table.GetAllPagesByNextPageState(keyspacesUrl),
        usableKeyspacesTable = Table.SelectRows(keyspacesTable, each not List.Contains(hiddenAstraKeyspaces, [keyspace_name])),
        removed = Table.SelectColumns(usableKeyspacesTable,{"keyspace_name"}),
        removedSorted = Table.Sort(removed, {"keyspace_name"}),
        renamed = Table.RenameColumns(removedSorted, {{"keyspace_name", "Keyspace"}}),
        // Add Data as a calculated column
        withData = Table.AddColumn(renamed, "Data", each AstraDB.getTablesForKeyspace(databaseID, region, [Keyspace])),
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

// SCHEMA handling - get all tables
AstraDB.getTablesForKeyspace = (databaseID as text, region as text, keyspace as text) =>
    let
        tablesUrl = makeRestAPIUrl(databaseID, region, "schemas/keyspaces/" & keyspace & "/tables"),
        // This (the 'try' and passing interceptUnauthorized=true) is to catch keyspaces we don't have access to, plus...
        // Stargate BUG: with limited-scope tokens, empty keyspaces error as well ("401 Unauthorized").
        tablesTable = try
            let
                tablesTableTry = getSinglePage(tablesUrl, null, true)
            in
                tablesTableTry
        catch
            (e) => #table(
                type table[Table=text, Data=[Table], ItemKind=text, ItemName=text, IsLeaf=logical],
                {}
            ),
        //
        navTable = if (Table.IsEmpty(tablesTable)) then
            #table(
                type table[Table=text, Data=[Table], ItemKind=text, ItemName=text, IsLeaf=logical],
                {}
            )
        else
            let
                removed = Table.SelectColumns(tablesTable, {"name"}),
                renamed = Table.RenameColumns(removed,{{"name", "Table"}}),
                // Add Data as a calculated column
                withData = Table.AddColumn(renamed, "Data", each AstraDB.getDataForTable(databaseID, region, keyspace, [Table])),
                // Add ItemKind and ItemName as fixed text values
                withItemKind = Table.AddColumn(withData, "ItemKind", each "Table", type text),
                withItemName = Table.AddColumn(withItemKind, "ItemName", each "Table", type text),
                // Indicate that the node should not be expandable
                withIsLeaf = Table.AddColumn(withItemName, "IsLeaf", each true, type logical),
                // Generate the nav table
                navTable = Table.ToNavigationTable(withIsLeaf, {"Table"}, "Table", "Data", "ItemKind", "ItemName", "IsLeaf")
            in
                navTable
    in
        navTable
;

// SCHEMA handling - cql-to-M type conversion
cqlTypeToMType = (cqlType as text, isMandatory as logical) as type =>
    let
        _ct = Text.Lower(cqlType),
        baseType =
            if (_ct = "ascii")      then type nullable text     else
            if (_ct = "bigint")     then type nullable number   else
            if (_ct = "blob")       then type nullable binary   else
            if (_ct = "boolean")    then type nullable logical  else
            if (_ct = "counter")    then type nullable number   else
            if (_ct = "date")       then type nullable date     else
            if (_ct = "decimal")    then type nullable number   else
            if (_ct = "double")     then type nullable number   else
            if (_ct = "float")      then type nullable number   else
            if (_ct = "inet")       then type nullable text     else
            if (_ct = "int")        then type nullable number   else
            if (_ct = "smallint")   then type nullable number   else
            if (_ct = "text")       then type nullable text     else
            if (_ct = "time")       then type nullable time     else
            if (_ct = "timestamp")  then type nullable datetime else
            if (_ct = "timeuuid")   then type nullable text     else
            if (_ct = "tinyint")    then type nullable number   else
            if (_ct = "uuid")       then type nullable text     else
            if (_ct = "varint")     then type nullable number   else
            type any,
        completeType = if isMandatory then Type.NonNullable(baseType) else baseType
    in
        completeType
;

// SCHEMA handling - query Astra REST API and construct a table schema
// Note: We cannot reuse getSinglePage here since the "data" response field is not a list of records for this endpoint.
AstraDB.getSchemaForTable = (databaseID as text, region as text, keyspace as text, tableName as text) as table =>
    let
        tableSchemaUrl = makeRestAPIUrl(databaseID, region, "schemas/keyspaces/" & keyspace & "/tables/" & tableName),
        token = Extension.CurrentCredential()[Key],
        requestHeaders = [
            accept="application/json",
            #"X-Cassandra-Token"=token
        ],
        // Error handling for the request+parsing part
        data = try
            let
                response = Web.Contents(
                    tableSchemaUrl,
                    [
                        Headers = requestHeaders,
                        Timeout = httpTimeout
                    ]
                ),
                body = Json.Document(response)
            in
                body[data]
        catch
            (e) => httpExceptionToErrorMessage(e[Reason], e[Message], tableSchemaUrl),
        // End of request+parsing-part custom error handling
        columns = Table.FromRecords(data[columnDefinitions]),
        // which columns are in the primary key, i.e. are non-nullable?
        keyColumnsPK = data[primaryKey][partitionKey],
        keyColumnsCC = data[primaryKey][clusteringKey],
        keyColumns = List.Combine({keyColumnsPK, keyColumnsCC}),

        // prepare the schema as table with creation of the types column
        schemaAsTable = Table.FromRecords(data[columnDefinitions], {"name", "typeDefinition"}),
        enrichedSchemaAsTable = Table.AddColumn(
            schemaAsTable,
            "enrichedTypeDefinition",
            each cqlTypeToMType([typeDefinition], List.Contains(keyColumns,[name])),
            type type
        ),
        cleanedSchemaAsTable = Table.SelectColumns(enrichedSchemaAsTable, {"name", "enrichedTypeDefinition"}),
        renamedSchema = Table.RenameColumns(cleanedSchemaAsTable, {
            {"name", "Name"},
            {"enrichedTypeDefinition", "Type"}
        })
    in
        renamedSchema
;

// DATA handling - get a single page from Astra Rest API
getSinglePage = (url as text, optional pageState as text, optional interceptUnauthorized as logical) as table =>
    // If pageState is passed, it is appended to the URL at the last minute here
    // This function works for paginated requests as well as no-pagination endpoints.
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
        // handling optional 401 interception
        unauthHandling = if (interceptUnauthorized = true) then
            [ManualStatusHandling={401}]
        else
            [],
        // Error handling for the request part
        body = try
            let
                response = Web.Contents(
                    requestUrl,
                    Record.Combine({
                        [
                            Headers = requestHeaders,
                            Timeout = httpTimeout
                        ],
                        unauthHandling
                    })
                )
            in
                Json.Document(response)
        catch
            (e) => httpExceptionToErrorMessage(e[Reason], e[Message], requestUrl),
        // End of request-part custom error handling
        nextPageState = Record.FieldOrDefault(body, "pageState"),
        // Error handling for the data-extraction part
        // Warning: to avoid errors piling up (actually, nesting into each other) we do this null check here.
        // (otherwise, even if the above errors in the catch, the below subfield extraction would execute anyway)
        data = if body = null then
            null
        else
            try
                Table.FromRecords(body[data])
            catch
                (e) => httpExceptionToErrorMessage(e[Reason], e[Message], requestUrl)
        // End of data-extraction-part custom error handling
    in
        data meta [nextPageState = nextPageState]
;

// DATA handling - get (paginated) rows for a table
AstraDB.getDataForTable = (databaseID as text, region as text, keyspace as text, tableName as text) =>
    let
        tableSchema = AstraDB.getSchemaForTable(databaseID as text, region as text, keyspace as text, tableName as text),
        tableUrl = makeRestAPIUrl(databaseID, region, "keyspaces/" & keyspace & "/" & tableName & "/rows" & tableUrlPageSizeSpecifier),
        dataTable = Table.GetAllPagesByNextPageState(tableUrl),
        withSchema = SchemaTransformTable(dataTable, tableSchema)
    in
        // dataTable
        withSchema
;

// PAGINATION
// (see: https://learn.microsoft.com/en-us/power-query/samples/trippin/5-paging/readme)
// The two functions 'GenerateByPage' and 'GetAllPagesByNextPageState' implement
// a progressive all-page-collation of results along the lines outlined in the above link.
// The big difference is the "next page" handling, which here is a page-state string
// and not a full link. So throughout this pagination we keep a separate concept
// of "bare url" and "url with page-state indication".

// Generate a full list of results page after page, given a function to build the next page.
Table.GenerateByPage = (getNextPage as function) as table =>
    // getNextPage takes a single argument and is expected to return a nullable table
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

// Generate the whole result set from the first page, with knowledge on how to extract
// the request for 'next page'. This expects that 'getSinglePage' encodes
// the state for the next page in the metadata for the returned page.
Table.GetAllPagesByNextPageState = (url as text, optional interceptUnauthorized as logical) as table =>
    // Here we use GenerateByPage with a certain explicit 'getNextPage' implementation.
    // GenerateByPage will keep asking for more pages until this 'getNextPage' returns null
    Table.GenerateByPage((previous) =>
        let
            // if previous is null, then this is our first page of data
            wasFirst = (previous = null), // boolean
            // if not first page, it's relevant to check if there is a next page or not
            nextPageState = Value.Metadata(previous)[nextPageState]?, // nullable
            page = if (wasFirst) then
                // we ask for at least one page
                getSinglePage(url, null, interceptUnauthorized)
            else (
                if (nextPageState <> null) then
                    // there is a new page to ask
                    getSinglePage(url, nextPageState, interceptUnauthorized)
                else
                    // we've exhausted the table
                    null
            )
        in
            page
    );


// ERROR handling - translate HTTP exception into Astra-friendly messages
httpExceptionToErrorMessage = (eReason as text, eMessage as text, requestUrl as text) as any =>
    // this function is structured after careful experimentation with various endpoint failure modes

    if eReason = "DataSource.Error" then
        if Text.Contains(eMessage, "be resolved", Comparer.OrdinalIgnoreCase) then
            error Extension.LoadString("AstraDBErrMessageWrongConnParam") & " (" & requestUrl & ")"
        else if Text.Contains(eMessage, "not found", Comparer.OrdinalIgnoreCase) then
            error Extension.LoadString("AstraDBErrMessageEndpointNotFound") & " (" & requestUrl & ")"
        else if Text.Contains(eMessage, "timed out", Comparer.OrdinalIgnoreCase) then
            error Extension.LoadString("AstraDBErrMessageTimeout") & " (" & requestUrl & ")"
        else if Text.Contains(eMessage, "bad request", Comparer.OrdinalIgnoreCase) then
            error Extension.LoadString("AstraDBErrMessageCheckDBStatus") & " (" & requestUrl & ")"
        else
            error Extension.LoadString("AstraDBErrMessageUnknownReason") & " """ & eMessage & """" & " (" & requestUrl & ")"
    else if eReason = "Expression.Error" then
        error Extension.LoadString("AstraDBErrMessageInsufficientResponse") & " """ & eMessage & """" & " (" & requestUrl & ")"
    else if eReason = "DataFormat.Error" then
        error Extension.LoadString("AstraDBErrMessageMalformedResponse") & " (" & requestUrl & ")"
    else
        error Extension.LoadString("AstraDBErrMessageUnexpectedErrorA") & " """ & eReason & """" & Extension.LoadString("AstraDBErrMessageUnexpectedErrorB") & " """ & eMessage & """" & " (" & requestUrl & ")"
;

// Main entrypoint function that gets exposed:
[DataSource.Kind="AstraDB", Publish="AstraDB.Publish"]
// Actual entrypoint
shared AstraDB.Contents = AstraDB.getKeyspacesTableReadCall;
// shared AstraDB.Contents = AstraDB.getKeyspacesSchemaCall; // Deprecated in favor of the above (which works on a DB-scoped token)
//
// "Tables in a keyspace" entrypoint
// shared AstraDB.Contents = AstraDB.getTablesForKeyspace;
//
// "Data in a table" entrypoint(s)
// shared AstraDB.Contents = AstraDB.getDataForTable;
// shared AstraDB.Contents = AstraDB.getSchemaForTable;

// just a call to the Astra DB REST API for TestConnection
[DataSource.Kind="AstraDB"]
shared AstraDB.astraTestConnection = (databaseID as text, region as text) =>
    let
        keyspacesUrl = makeRestAPIUrl(databaseID, region, "keyspaces/system_schema/keyspaces/rows"),
        returned = getSinglePage(keyspacesUrl)
    in
        returned
;

// Data Source Kind description
AstraDB = [
    TestConnection = (dataSourcePath) =>
        let
            json = Json.Document(dataSourcePath),
            databaseID = json[databaseID],
            region = json[region]
        in
            { "AstraDB.astraTestConnection", databaseID, region }
    ,
    Authentication = [
        Key = [
            KeyLabel=Extension.LoadString("DBTokenFieldName")
        ]
    ],
    Label = "Astra DB"
];

// Data Source UI publishing description
AstraDB.Publish = [
    Beta = true,
    Category = "Database",
    ButtonText = { Extension.LoadString("ButtonTitle"), Extension.LoadString("ButtonHelp") },
    LearnMoreUrl = "https://astra.datastax.com/",
    SourceImage = AstraDB.Icons,
    SourceTypeImage = AstraDB.Icons
];

AstraDB.Icons = [
    Icon16 = { Extension.Contents("AstraDB16.png"), Extension.Contents("AstraDB20.png"), Extension.Contents("AstraDB24.png"), Extension.Contents("AstraDB32.png") },
    Icon32 = { Extension.Contents("AstraDB32.png"), Extension.Contents("AstraDB40.png"), Extension.Contents("AstraDB48.png"), Extension.Contents("AstraDB64.png") }
];
