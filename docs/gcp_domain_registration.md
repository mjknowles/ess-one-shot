# 🌐 Registering a New Domain using Google Cloud CLI

This guide walks you through how to register a new domain name in Google Cloud using the `gcloud` command-line tool.  
You only need to follow these steps once to set up your domain.

---

## 🧰 Prerequisites

Before starting, make sure you have:

1. A **Google Cloud account** → [https://console.cloud.google.com](https://console.cloud.google.com)
2. The **gcloud CLI** installed  
   👉 Install instructions: [https://cloud.google.com/sdk/docs/install](https://cloud.google.com/sdk/docs/install)
3. A **project with billing enabled**

---

## 🪄 Step 1. Log in and list your projects

Open a terminal or command prompt and log in:

```bash
gcloud auth login
gcloud projects list
gcloud config set project dns-infra-474704
gcloud services enable domains.googleapis.com
gcloud domains registrations search-domains mjknowles
gcloud domains registrations get-register-parameters mjknowles.dev
gcloud dns managed-zones create mjknowles-dev-zone \
  --description="DNS zone for mjknowles.dev" \
  --dns-name="mjknowles.dev."
gcloud domains registrations register mjknowles.dev
```

## 🧹 Step 2. Tear down (optional)

When you no longer need the DNS zone (for example, to stop Cloud DNS billing), delete it from the DNS project:

```bash
gcloud dns managed-zones delete mjknowles-dev-zone \
  --project dns-infra-474704
```

If you also want to relinquish the domain itself, cancel the registration and let it expire:

```bash
gcloud domains registrations delete mjknowles.dev \
  --project dns-infra-474704
```

Keep in mind that deleting the zone removes all DNS records, so any services pointing at `mjknowles.dev` will stop resolving immediately.
