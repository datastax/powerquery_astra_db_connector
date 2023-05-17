## README for developers

This summarizes the steps necessary to develop with this connector.

Pre-requisites:

- You must work on Windows;
- You need Visual Studio Code;
- Install the "Power Query SDK" plugin for Visual Studio Code as instructed [here](https://learn.microsoft.com/en-us/power-query/install-sdk);
- Install PowerBI Desktop, for example following the link [here](https://learn.microsoft.com/en-us/power-query/power-query-ui).

### Running in "dev mode"

Dev mode will just show a trimmed down, non-interactive version of the connector output.

Open this project in VSCode, create the `*.query.pq` file from the corresponding provided template, adjust as needed (i.e. replace with your Database ID and region).

Locate the "POWER QUERY SDK" bar below VSCode's Explorer left-hand navbar, expand it. It should have detected that the project is a PowerQuery extension and allow for a "Set credential" operation. Follow it to set e.g. your (DB Admin) Astra DB token. _(Note: this should be done after adjusting the file above, as each change will trigger the need for new credentials.)_

Now right-click on the `*.query.pq` file and pick "Evaluate current power query file". It will compile the extension and run it: in a few seconds you will see the output in a "PQTest result" panel on the right.

### Running in PowerBI Desktop

To run your compiled extension, you will have to enable untrusted connectors
in PowerBI Desktop (as opposed to the self-signed distributed connector):
check [this link](https://learn.microsoft.com/en-us/power-query/install-sdk#power-bi-desktop) for how to do it.

You will find a MEZ file in `bin/AnyCPU/Debug` in the project directory if you ran it at least once with VSCode:
copy it to (your version of) `C:\Users\USER\Documents\Power BI Desktop\Custom Connectors` and open PowerBI,
looking for the "Astra DB" data source after clicking "Get Data".

From this point, usage of the extension is as described in the main guide.
