import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";

// Config values
const config = new pulumi.Config();
const dbName = config.get("dbName") || "essdb";
const dbUser = config.get("dbUser") || "essadmin";
const dbPassword = config.requireSecret("dbPassword"); // stored securely in Pulumi config
const region = config.get("region") || "us-central1";

// Optionally, create a network if you don’t already have one
const network = new gcp.compute.Network("ess-network", {
  autoCreateSubnetworks: false,
});

// (Optional) Subnet for private IP connectivity
const subnet = new gcp.compute.Subnetwork("ess-subnet", {
  ipCidrRange: "10.10.0.0/24",
  region: region,
  network: network.id,
  purpose: "PRIVATE",
});

// Private service connection for Cloud SQL
const privateConnection = new gcp.servicenetworking.Connection("ess-sql-conn", {
  network: network.id,
  service: "servicenetworking.googleapis.com",
  reservedPeeringRanges: ["10.10.0.0/24"],
});

// Cloud SQL instance
const instance = new gcp.sql.DatabaseInstance(
  "ess-postgres-instance",
  {
    databaseVersion: "POSTGRES_15",
    region: region,
    settings: {
      tier: "db-custom-1-3840", // 1 vCPU, 3.75GB RAM
      ipConfiguration: {
        ipv4Enabled: false,
        privateNetwork: network.id,
      },
      availabilityType: "REGIONAL", // or ZONAL
      backupConfiguration: {
        enabled: true,
      },
      activationPolicy: "ALWAYS",
      diskSize: 20,
      diskType: "PD_SSD",
    },
    deletionProtection: false, // easy teardown during dev
  },
  { dependsOn: [privateConnection] }
);

// Create a database inside
const database = new gcp.sql.Database("ess-database", {
  name: dbName,
  instance: instance.name,
});

// Create a user
const user = new gcp.sql.User("ess-user", {
  instance: instance.name,
  name: dbUser,
  password: dbPassword,
});

// Export connection info
export const connectionName = instance.connectionName;
export const dbConnectionString = pulumi.interpolate`postgresql://${dbUser}:${dbPassword}@${instance.connectionName}/${dbName}`;
