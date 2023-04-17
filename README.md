# astra_db_connector

A PowerQuery connector to access tables in Astra DB, backed by the REST API.

_Status as of 2023-04-14: very preliminary!_

## Dev mode setup

Pre-requisites:

- You must work on Windows;
- You need Visual Studio Code;
- Install the "Power Query SDK" plugin for Visual Studio Code as instructed [here](https://learn.microsoft.com/en-us/power-query/install-sdk);
- Install PowerBI Desktop, for example following the link [here](https://learn.microsoft.com/en-us/power-query/power-query-ui).

### Running in "dev mode"

Dev mode will just show a trimmed down, non-interactive version of the connector output.

Open this project in VSCode, open the `*.query.pq` file, adjust as needed (i.e. replace with your Database ID and region).

Locate the "POWER QUERY SDK" bar below VSCode's Explorer left-hand navbar, expand it. It should have detected that the project is a PowerQuery extension and allow for a "Set credential" operation. Follow it to set e.g. your (DB Admin) Astra DB token. _(Note: this should be done after adjusting the file above, as each change will trigger the need for new credentials.)_

Now right-click on the `*.query.pq` file and pick "Evaluate current power query file". It will compile the extension and run it: in a few seconds you will see the output in a "PQTest result" panel on the right.

### Running in PowerBI Desktop

For more extensive usage, pick the `*.mez` file created in `bin/AnyCPU/Debug` and copy it to (your version of) `C:\Users\USER\Documents\Power BI Desktop\Custom Connectors`.

Then open PowerBI and make sure you [enable untrusted extensions](https://learn.microsoft.com/en-us/power-query/install-sdk#power-bi-desktop) in the global settings.

Now you can "Get Data" and start using the new connector.
