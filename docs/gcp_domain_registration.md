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
gcloud config set project PROJECT_ID
gcloud services enable domains.googleapis.com
gcloud domains registrations search-domains KEYWORD
gcloud domains registrations get-register-parameters YOURSITE.com
gcloud dns managed-zones create YOURSITE-zone \
  --description="DNS zone for YOURSITE.com" \
  --dns-name="YOURSITE.com."
  gcloud domains registrations register YOURSITE.com
```
