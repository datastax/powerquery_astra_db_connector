# "Astra DB" Power Query connector

A PowerQuery connector to access tables in Astra DB, backed by the REST API.

## Usage instructions

_Note: A more detailed user guide is going to be published on [Awesome Astra](https://awesome-astra.github.io) and it will be announced here shortly._

The following instructions cover usage in PowerBI Desktop and PowerBI Service, the latter
backed by a (personal-mode) On-premises Data Gateway.

The current status of this connector is: beta self-signed. The certification process is underway.

## PowerBI Desktop

Obtain the latest PQX file from the [releases](https://github.com/hemidactylus/powerquery_astra_db_connector/releases)
page and place the file in (your equivalent for) ``C:\Users\USER\Documents\Power BI Desktop\Custom Connectors``

At the moment this is a self-signed connector, so you can either list the certificate thumbprint as "trusted" in your system (recommended) or alternatively enable untrusted extensions in PowerBI.

### Trusted certificate thumbprint

To **mark the thumbprint as trusted**, the steps are outlined at [this link](https://learn.microsoft.com/en-us/power-bi/connect-data/desktop-trusted-third-party-connectors):

- Open `regedit` as admin;
- Locate the key `HKEY_LOCAL_MACHINE\Software\Policies\Microsoft\Power BI Desktop`, creating it if absent;
- In this key, create a multi-string (`REG_MULTI_SZ`) entry named `TrustedCertificateThumbprints`;
- The value must be a newline-separated string (right-click, Modify to edit as text), each with a trusted thumbprint;
- Enter the thumbprint of the certificate used to sign the connector releases:

```
1BB690F359432E849D06FDEA4E82573B279AAD75
```

### Enable untrusted connectors

Alternatively, you can lower the security level of PowerBI Desktop as outlined [here](https://learn.microsoft.com/en-us/power-query/install-sdk#power-bi-desktop):

`File` => `Options and Settings` => `Options` => `Security` => in "Data Extensions", choose _Allow any data extension to load without validation or warning_. Then restart PowerBI Desktop.

### Using the connector

Now you can start PowerBI Desktop, choose "Get Data", search for the "Astra DB" connector and select it.

You will be asked for the connection details: [database ID](https://awesome-astra.github.io/docs/pages/astra/faq/?h=database+id#where-should-i-find-a-database-identifier) and [region](https://awesome-astra.github.io/docs/pages/astra/faq/?h=database+id#where-should-i-find-a-database-region-name).

Next, you will provide the "Database Token" (the string starting with `AstraCS:...`) as credentials.

At the very least, these are the permissions required for a token to work with this connector:

- The token must have, in Table Permissions, (1) Select Table and (2) Describe Table, and in API Access also (3) REST;
- It is OK if the token has access limited to just the one DB that is being used;
- If the token is disallowed on certain keyspaces, they will show up as empty in the connector's resulting navigation table.

For more on Astra DB Tokens, see [here](https://awesome-astra.github.io/docs/pages/astra/create-token/).

Once the token credentials is provided, you will be able to browse keyspaces and the tables contained therein.


## PowerBI Service

_Note: usage in PowerBI Service requires having completed the PowerBI Desktop setup first._

As this is still a self-signed connector and is just now undergoing the certification process,
for the time being you will need to rely on a Personal Data Gateway: see [here](https://learn.microsoft.com/en-us/data-integration/gateway/service-gateway-install#download-and-install-a-personal-mode-gateway) for more instructions on how to install it in your on-premises machine(s).

The Gateway should find the connectors in the same directory as PowerBI Desktop. Make sure you have logged in with your cloud account both on PowerBI Desktop and the Gateway.

Now create a report with PowerBI Desktop, then save it (locally) and choose, in the "File" menu, "Publish" => "Publish to PowerBI". Pick your preferred destination workspace.

After the publishing succeeds, you can log in to your PowerBI Service account and you will find your report there. You will have to enter the credentials again once (do that by triggering a data source refresh and checking the data source settings afterwards).

More information can be found [here](https://community.powerbi.com/t5/Community-Blog/Custom-Data-Connector-How-to-Deploy-and-Test/ba-p/862678).


## Information for developers

See the [README for developers](README_devs.md)
