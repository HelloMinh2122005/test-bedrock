import asyncio
import json
import os
import urllib.parse
import boto3
import requests
from dotenv import load_dotenv
from browser_use import Agent, Browser
# Native LLM adapter from browser_use for AWS Bedrock
from browser_use.llm.aws import ChatAWSBedrock
# Official AWS SDK to create and manage AgentCore Browser sessions
from bedrock_agentcore.tools.browser_client import browser_session

# Load environment variables from .env file
load_dotenv()

AWS_PROFILE_NAME = os.getenv("AWS_PROFILE", "default")
AWS_REGION_NAME = os.getenv("AWS_REGION", "ap-southeast-2")
BEDROCK_MODEL_ID = os.getenv("BEDROCK_MODEL_ID", "amazon.nova-pro-v1:0")

# Set AWS_PROFILE environment variable for browser_session SDK
os.environ["AWS_PROFILE"] = AWS_PROFILE_NAME


def generate_console_signin_url(region: str) -> str:
    """
    Use sts:GetFederationToken to generate temporary credentials (ASIA...)
    directly from the active IAM User of the specified profile, then generate a Federated Sign-in URL.
    """
    session = boto3.Session(profile_name=AWS_PROFILE_NAME)
    sts_client = session.client('sts')
    
    print(f"🔄 Generating temporary credentials via GetFederationToken (Profile: {AWS_PROFILE_NAME})...")
    response = sts_client.get_federation_token(
        Name="AuditAgentSession",
        PolicyArns=[
            {"arn": "arn:aws:iam::aws:policy/SecurityAudit"}
        ]
    )
    temp_creds = response['Credentials']

    session_data = {
        "sessionId": temp_creds['AccessKeyId'],
        "sessionKey": temp_creds['SecretAccessKey'],
        "sessionToken": temp_creds['SessionToken']
    }

    federation_url = "https://signin.aws.amazon.com/federation"
    response = requests.get(
        federation_url,
        params={
            "Action": "getSigninToken",
            "Session": json.dumps(session_data)
        }
    )
    response.raise_for_status()
    signin_token = response.json()["SigninToken"]

    destination = f"https://{region}.console.aws.amazon.com/rds/home?region={region}#databases:"

    signin_url = (
        f"{federation_url}?Action=login"
        f"&Issuer=AuditAgent"
        f"&Destination={urllib.parse.quote(destination)}"
        f"&SigninToken={signin_token}"
    )
    return signin_url


async def run_agent(ws_url: str, headers: dict, signin_url: str):
    """Run browser agent using Federated Sign-in URL."""
    browser = Browser(cdp_url=ws_url, headers=headers)

    # === Define the AI LLM ===
    boto_session = boto3.Session(profile_name=AWS_PROFILE_NAME)
    
    # Use Amazon Nova Pro (or chosen model in .env) as the AI brain
    llm = ChatAWSBedrock(
        model=BEDROCK_MODEL_ID,
        aws_region=AWS_REGION_NAME,
        session=boto_session,
        max_tokens=4096,
    )

    prompt_audit = f"""
    1. Navigate directly to this Federated Sign-in URL to automatically log into the AWS Console:
       {signin_url}
    2. Wait for the RDS Databases page to load completely.
    3. Verify the list of displayed Database Instances.
    4. If there are databases, navigate into each database, go to the 'Configuration' tab, and find the 'Encryption' property.
    5. Take a full-page screenshot of the Encryption status page of each database to serve as audit evidence.
    6. Save all captured screenshots in the 'evidence/' directory.
    """

    agent = Agent(
        task=prompt_audit,
        llm=llm,
        browser=browser
    )

    print(f"AI Agent starting AWS Console audit via Federated Login (Model: {BEDROCK_MODEL_ID})...")
    try:
        await agent.run()
    finally:
        await browser.close()


def main():
    try:
        signin_url = generate_console_signin_url(AWS_REGION_NAME)
        print("✅ Successfully generated AWS Console Federated Sign-in URL.")
    except Exception as e:
        print(f"❌ Failed to generate Sign-in URL: {e}")
        return

    # === Create Browser session via AgentCore SDK (requires environment variable for profile) ===
    with browser_session(AWS_REGION_NAME) as client:
        ws_url, headers = client.generate_ws_headers()

        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        try:
            task = loop.create_task(run_agent(ws_url, headers, signin_url))
            loop.run_until_complete(task)
        finally:
            loop.close()


if __name__ == "__main__":
    main()