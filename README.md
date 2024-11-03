<h1 align="center">
<a href="https://cooltext.com"><img src="Bounty VPS.jpg" width="500" alt="Bounty-VPS" />
</h1>
<h4 align="center">Bug Bounty Easy Vps Setup</h4>
<p align="center">
  <a href="https://github.com/sudosuraj/Bounty-VPS">
    <img src="https://img.shields.io/badge/Project-Bounty--VPS-green">
  </a>
   <a href="[https://github.com/mrco24/OK-VPS](https://github.com/sudosuraj/Bounty-VPS)">
    <img src="https://img.shields.io/static/v1?label=Update&message=V1.0&color=green">
  </a>
  <a href="https://twitter.com/sudosuraj">
      <img src="https://img.shields.io/twitter/follow/sudosuraj?style=social">
  </a>
</p>

# About
 Bug Bounty Setup Tools On Fresh VPS. This scripts automatically installs top bug bounty tools and set up environment in newly installed VPS or Linux Operating System.
 ### This scrips:
 - Download Setup Go landguage
 - Setup Python3 Env for pentesting
 - Download most of the tools used in penetration testing and bug bounty

# Installation
```
sudo apt-get update -y && sudo apt-get install git -y && cd /tmp && git clone https://github.com/sudosuraj/Bounty-VPS.git && cd Bounty-VPS && chmod +x bounty-vps.sh && sudo bash ./bounty-vps.sh
```
# 🛠️ Tools List

These tools are primarily for reconnaissance, enumeration, and vulnerability scanning.

## Reconnaissance & Enumeration
- **subfinder** - Subdomain discovery
- **assetfinder** - Finds related assets (domains)
- **katana** - Web crawler
- **gau** - Fetches archived URLs
- **amass** - In-depth DNS enumeration
- **crobat** - Subdomain enumeration
- **chaos** - Enumerates subdomains from ProjectDiscovery’s Chaos dataset
- **gotator** - Permutation-based subdomain generator
- **cf-check** - Cloudflare IP checker
- **gowitness** - Web screenshot tool
- **httpx** - HTTP probing
- **httprobe** - Probes for HTTP servers
- **gospider** - Web spider
- **subzy** - Subdomain takeover scanner

## Web & Network Scanning
- **dnsx** - DNS resolver and probe
- **puredns** - Fast recursive DNS resolver
- **shuffledns** - DNS enumeration using bruteforce and wordlist
- **ffuf** - Fast web fuzzer
- **gobuster** - Directory, DNS, and VHost busting tool
- **nuclei** - Vulnerability scanner
- **interactsh-client** - Interaction-based payloads
- **httpx** - HTTP probing

## OSINT & Data Gathering
- **waybackurls** - Fetch URLs from the Wayback Machine
- **socialhunter** - Social media data finder
- **github-subdomains** - Finds subdomains in GitHub repositories
- **bxss** - Blind XSS payload generator
- **Jeeves** - Enumeration tool
- **tok** - Enumeration tool

## Scripting & Miscellaneous Utilities
- **anew** - Appends unique lines to a file
- **qsreplace** - Replaces query string values
- **gron** - Converts JSON into greppable data
- **fff** - Fast file finder
- **unfurl** - Extracts URLs from input
- **mapcidr** - Subnetting tool
- **cent** - Nuclei templates manager
- **notify** - Notification manager for vulnerabilities

## Injection & Security Testing
- **dalfox** - XSS scanner
- **kxss** - Finds potential XSS points
- **Gxss** - XSS payload generator
- **error-sql** - SQL injection error-based tester
- **time-sql** - SQL injection time-based tester

---

# 🐍 Python Tools

These tools are primarily for web application testing and OSINT.

## Web & Application Testing
- **arjun** - HTTP parameter discovery tool
- **GitHacker** - Finds secrets in Git repositories
- **SecretFinder** - Finds sensitive keys in JavaScript files
- **LinkFinder** - Extracts URLs from JavaScript files
- **uro** - URL parser
- **urless** - URL manipulation tool

## OSINT & Data Extraction
- **crtsh** - Certificate transparency log searcher
- **jsbeautifier** - Beautifies JavaScript code
- **lxml** - XML and HTML parsing library

---

# 🧰 Kali Linux Tools

These tools cover a broad spectrum of penetration testing, including network scanning, web application assessment, and wireless security.

## Network Scanning
- **nmap** - Network scanner
- **masscan** - Fast port scanner
- **p0f** - Passive OS fingerprinting
- **dnsenum** - DNS enumeration tool
- **dnsmap** - DNS map generator
- **dnstracer** - Traces DNS path
- **wireshark** - Network packet analyzer

## Web Application Security
- **sqlmap** - SQL injection tool
- **wpscan** - WordPress vulnerability scanner
- **arachni** - Web application vulnerability scanner
- **skipfish** - Web application security scanner
- **wfuzz** - Web fuzzer
- **w3af** - Web application attack and audit framework

## Exploitation Tools
- **metasploit** - Exploitation framework
- **beef-xss** - Browser exploitation framework
- **backdoor-factory** - Injects backdoors into binaries
- **weevely** - Web shell generator

## Password Cracking
- **hash-identifier** - Identifies hash types
- **john** - Password cracker
- **rainbowcrack** - Uses rainbow tables for password cracking
- **patator** - Multi-purpose brute-forcer

## Wireless Security
- **aircrack-ng** - Wireless security auditing
- **kismet** - Wireless network detector
- **pixiewps** - Offline WPS attack tool
- **reaver** - WPA attack tool

## OSINT & Reconnaissance
- **theharvester** - Collects emails, subdomains, hosts, and more
- **recon-ng** - Reconnaissance framework
- **metagoofil** - Collects public documents from Google
- **fierce** - DNS reconnaissance tool
- **firewalk** - Traces firewall rules

---

### 🎉 Final Note
Once the script completes, your VPS will be fully set up for penetration testing and reconnaissance, with a wide range of tools installed.

