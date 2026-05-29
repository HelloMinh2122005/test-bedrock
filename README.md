# AWS Bedrock AgentCore Browser - Audit Agent

## 1. Provision Infrastructure

Run this inside the `terraform` directory:

```bash
cd terraform
terraform init
terraform apply -auto-approve
cd ..
```

## 2. Environment Setup

Create a `.env` file in the root directory:

```bash
cp .env.example .env
```

Fill in your configuration details in `.env`:

```env
AWS_PROFILE=
AWS_REGION=ap-southeast-2
AWS_ACCOUNT_ID=<put_your_account_id>
BEDROCK_MODEL_ID=amazon.nova-pro-v1:0
```

## 3. Install Dependencies

Set up virtual environment and install requirements:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
playwright install chromium
```

## 4. Run the Audit Agent

Start the security audit agent:

```bash
python main.py
```

Screenshots of RDS configuration will be saved in the `evidence/` directory.
