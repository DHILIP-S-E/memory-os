# Demo video voiceover

One section per scene. Each section has a matching audio file (`01-intro.wav` and so on).
"On screen" says what the footage shows while the narration plays.

## 01 Intro
On screen: login screen, sign in with the demo account, land on Today.

Most reminder apps only ask one question: what should I remind you about? Personal Memory OS also asks: what did I learn? You capture things, like notes, voice memos, photos and event pages, and AI turns them into reminders and memory you can search. Let me show you.

## 02 Today
On screen: Today tab. Progress card, tap Overdue, scroll through the tasks.

This is the Today screen. It greets me by name, shows my progress for the day, and lists my tasks. One tap on Overdue shows exactly what I have missed: a weekly review, a team standup and a cloud bill. Everything here is real data from my account.

## 03 Reminders
On screen: Reminders tab, switch filters, then New Reminder, Natural Language tab, type "Call the bank every Monday at 10 AM", Parse with AI.

On the Reminders tab I can filter by upcoming, recurring, deadlines and overdue, and mark any reminder done or snooze it. To add one, I just type a normal sentence: call the bank every Monday at 10 AM. Amazon Nova on Bedrock reads it and suggests a reminder with the title and the time. I can edit it, or create it with one tap. Nothing is created without my confirmation.

## 04 Events
On screen: Add Event, Paste / AI Extract tab, paste a hackathon announcement, Extract with AI, then the Bedrock Agents Workshop event page.

Events are where it gets smart. I copy the text of a hackathon announcement and paste it in. Amazon Nova pulls out the event name and the dates, and suggests the event for me to review. I can edit it or create it in one tap. Every event also keeps the notes I captured there, each with its own AI summary, all in one place.

## 05 Capture
On screen: Capture tab with AI-ready notes, open a text note and type "I need to submit the prototype by October 20", then the voice note sheet.

Capture is for anything I want to keep: a photo, a voice note, a text note or a link. I just write it down and save, and saving is instant. In the background, a worker sends it to Amazon Nova, which writes a summary and picks out key points and deadlines. You can see those AI summaries under each note, marked AI ready. Voice notes work the same way.

## 06 Memory
On screen: Ask your memory, type "What did I learn about Bedrock Agents?", the answer with its source.

And I can ask questions about everything I have captured. What did I learn about Bedrock Agents? The answer comes only from my own notes, and it shows the source, here the Bedrock Agents Workshop, so I always know where it came from.

## 07 Alerts, offline and privacy
On screen: Profile. Export my data, Delete all data, home-screen widget.

Reminders reach me as notifications and email from the cloud, respecting quiet hours in my own timezone, and as local alarms on my phone, so they still fire when I am offline. On Android, a home screen widget shows my day. And my data is mine: I can export everything as JSON, or delete all of it, right from my profile.

## 08 Architecture and close
On screen: architecture slide, then the closing title.

Under the hood, a Flutter app and a web dashboard talk to a FastAPI backend on AWS App Runner. Files go to Amazon S3, a queue and worker process them with Amazon Nova on Bedrock, and a scheduler delivers reminders through Amazon SNS and email. The whole thing runs for under ten dollars a month, and it was built with Kiro and coding agents. Personal Memory OS. Never forget what you need to do, and never lose what you learned.
