# AWS Builder Center post: Personal Memory OS

Everything below is the text for the Builder Center project form.

## Title
Personal Memory OS: Reminders That Remember What You Learned, Built on AWS

## Description (282 characters)
A reminder app that also keeps what you capture: photos, voice notes and pasted event pages. Amazon Bedrock Nova turns them into events, deadlines and action items you confirm, then answers questions about your own notes. Flutter app and web dashboard run on App Runner and Amplify.

## Hackathon entry
- **App category:** Daily Life Enhancement
- **Focus track:** Community
- **Live application:** https://main.d1kc2e2qvfes41.amplifyapp.com
- **Source code:** https://github.com/DHILIP-S-E/memory-os
- **Proof of the coding agent working in AWS:** https://github.com/DHILIP-S-E/memory-os/blob/master/docs/hackathon/aws-agent-activity.md

## Try it (no sign-up needed)

Open the live app and sign in with the demo account, which is filled with sample reminders, events and notes:

- **Email:** `judge-demo@example.com`
- **Password:** `ZeroToShipped2026!`

Or tap "Sign up" and create your own account (email and password, no verification step).
Things to try: open **Events → Bedrock Agents Workshop → Summary**, then **Memory → "What did I learn about Bedrock Agents?"**, and add a new note on **Capture** and watch it get summarised.

## The idea

Most reminder apps answer "what should I remind you about?" Personal Memory OS also answers
"what did I learn?" You capture things (a note, a voice memo, a copied event page), and the app turns them
into reminders and searchable memory.

> Never forget what you need to do, and never lose what you learned.

## What it does

- **Paste or share an event page.** Amazon Bedrock extracts the title, dates, location and deadlines.
  You review and confirm. The app never creates anything silently.
- **Smart reminder plans.** Create a hackathon and get "Hackathon detected, create 7 reminders?" in one
  tap: 3 days, 1 day and 3 hours before each deadline, plus the event day.
- **Memory to action.** A note that says "I need to submit the prototype by October 20" becomes a
  suggestion: "You mentioned a deadline, create reminder?"
- **Ask your own notes.** Questions are answered from your captured events, with the source shown.
- **Daily brief and home-screen widget** (Android) showing what is overdue, today and coming up.
- **Works offline.** Reminders fire as local alarms, and changes sync when you reconnect.
- **Your data is yours.** Export everything as JSON, or delete your account and all its data.

## How the coding agent was used

I built this with coding agents connected to my AWS account through the AWS CLI. The project was started
in Kiro (specs, steering documents, scaffolding) and then built out, tested and deployed with Claude Code.
The agent:

- wrote the FastAPI backend, the Flutter app and the React web dashboard, with tests as it went;
- created the AWS resources (ECR repository, IAM roles, encrypted secrets, App Runner service,
  Amplify app) and deployed to them;
- verified the live service the way a user would: a real-browser test against the live site and an
  on-device test against the live backend, and used Amazon Bedrock to check the AI features.

**Proof:** every change the agent made in the AWS account is recorded by AWS CloudTrail. I exported them
with timestamps here:
https://github.com/DHILIP-S-E/memory-os/blob/master/docs/hackathon/aws-agent-activity.md

## Architecture

    Flutter app (Android)  ─┐
                            ├─►  AWS App Runner (FastAPI)  ─►  Amazon Bedrock (Nova)
    React web dashboard  ───┘          │                  ─►  Amazon S3 (private media)
    (AWS Amplify Hosting)              └──────────────────►  PostgreSQL (Neon)
                                       secrets: SSM Parameter Store

## AWS services used

| Service | What it does here |
|---|---|
| **Amazon Bedrock** | Amazon Nova Lite and Nova Pro parse reminders, extract events, summarise notes and answer questions (via the Converse API) |
| **AWS App Runner** | Runs the Python backend as a container, with HTTPS and autoscaling capped at 2 instances |
| **AWS Amplify Hosting** | Serves the React web dashboard |
| **Amazon S3** | Private storage for photos, voice notes and documents |
| **Amazon ECR** | Stores the backend image |
| **AWS Systems Manager Parameter Store** | Encrypted secrets, so nothing sensitive lives in code or env files |
| **AWS IAM** | A least-privilege role that may call only the two Nova models, one bucket and its own secrets |
| **AWS CloudTrail** | The audit record of what the agent changed |

The database is Neon (serverless PostgreSQL, free tier), the one non-AWS piece. A larger AWS-only
design (Lambda, Aurora, OpenSearch Serverless and more) is in the repo as an AWS CDK app but is not what is
deployed.

## What is and is not live

- **Live:** sign-up and sign-in, reminders (including recurring and conditional), events with smart
  reminder plans, text notes and links with automatic AI summaries and action items, event summaries,
  memory questions with sources, data export and account deletion.
- **Built but not part of the live setup:** the automatic photo/voice extraction pipeline (S3 to SQS to
  Bedrock Data Automation and Transcribe), cloud push notifications, and the semantic-search Knowledge Base.
  Photos and voice notes are stored, but they are not analysed automatically in the live deployment.

## How I made it reliable

- **Property-based tests** (Hypothesis) for reminder parsing, fire-time scheduling, quiet hours and
  action-item extraction. About 180 backend tests, 90 Flutter tests and 6 web unit tests.
- **AI output is untrusted.** Every model reply is validated and normalised before it can create anything,
  and ambiguous dates are shown to the user to confirm.
- **The AI never schedules.** It only interprets. Reminders are scheduled deterministically.
- **Run it for real.** Tests passed while real problems hid until I ran the migrations on a real database,
  the app on a real phone and the web app in a real browser. That is how I found a crash on the Summary tab,
  which is fixed and tested.

## What's next

Cloud push notifications (needs a Firebase project), turning the Knowledge Base search on, analysing
photos and voice notes in the live deployment, and iOS.
