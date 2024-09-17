#!/bin/bash
clear;
OR='\e[38;5;202m'
GR='\e[32m'
NL='\e[0m'
WH='\e[97m'
BL='\e[34m'

echo -e "
${OR} ${NL}
${OR}                 _                                 _ ${NL}
${OR}                | |                               (_)${NL}
${OR} ___  _   _   __| |  ___   ___  _   _  _ __  __ _  _ ${NL}
${WH}/ __|| | | | / _  | / _ \ / __|| | | ||  |__|/ _ || |${NL}
${WH}\__ \| |_| || (_| || (_) |\__ \| |_| || |  | (_| || |${NL}
${GR}|___/ \__ _| \__ _| \___/ |___/ \__ _||_|   \__ _|| |${NL}
${GR}                                                 _/ |${NL}
${GR}                                                |__/ ${NL}
"
echo -e "This script is made by" ${GR}sudosuraj${NL}

GOSETUP(){
	echo -e {OR}"Go lang Setup...";${NL}
	apt install unzip
	echo  -e  ${GR}Step 1: Downloading Go Package...${NL}
	cd /tmp && wget https://go.dev/dl/go1.23.0.linux-amd64.tar.gz
	echo  -e  ${GR}Step 2:Setting up go environment... ${NL}
	sudo tar -C /usr/local -xzf go1.23.0.linux-amd64.tar.gz
	mkdir $HOME/go
	mkdir $HOME/go/bin
	mkdir $HOME/go/pkg
	mkdir $HOME/go/src
	echo 'if [ -d "$HOME/go" ]; then
    	GOPATH=$HOME/go
    	GOROOT=/usr/local/go
    	PATH=$PATH:$GOROOT/bin:$GOPATH/bin
	fi' >> ~/.bashrc
	. ~/.bashrc & source ~/.bashrc
	echo -e ${GR}Step 3: Verify the installation...${NL}
	which go
	go version
	echo -e ${GR}Successfully installed $(go version)${NL}
}

GOTOOLS() {
    echo -e ${OR}"Go Tools Setup...";${NL}
    go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest 
    go install -v github.com/tomnomnom/anew@latest 
    go install github.com/tomnomnom/assetfinder@latest
    go install github.com/projectdiscovery/katana/cmd/katana@latest 
    go install github.com/tomnomnom/waybackurls@latest 
    go install github.com/hakluke/hakrawler@latest 
    go install github.com/d3mondev/puredns/v2@latest 
    go install -v github.com/projectdiscovery/dnsx/cmd/dnsx@latest 
    go install github.com/lc/gau/v2/cmd/gau@latest 
    go install github.com/utkusen/socialhunter@latest 
    go install -v github.com/PentestPad/subzy@latest 
    go install github.com/003random/getJS/v2@latest 
    go install -v github.com/projectdiscovery/shuffledns/cmd/shuffledns@latest 
    go install github.com/gwen001/github-subdomains@latest 
    go install -v github.com/owasp-amass/amass/v4/...@master 
    go install github.com/cgboal/sonarsearch/cmd/crobat@latest 
    go install -v github.com/projectdiscovery/mapcidr/cmd/mapcidr@latest 
    go install -v github.com/projectdiscovery/chaos-client/cmd/chaos@latest 
    go install github.com/Josue87/gotator@latest 
    go install github.com/glebarez/cero@latest 
    go install -v github.com/dwisiswant0/galer@latest  
    go install -v github.com/c3l3si4n/quickcert@HEAD 
    go install -v github.com/projectdiscovery/shuffledns/cmd/shuffledns@latest 
    go install github.com/sensepost/gowitness@latest 
    go install -v github.com/projectdiscovery/httpx/cmd/httpx@latest 
    go install github.com/tomnomnom/httprobe@latest 
    go install github.com/jaeles-project/gospider@latest 
    go install github.com/mrco24/parameters@latest 
    go install github.com/tomnomnom/gf@latest  
    go install github.com/mrco24/otx-url@latest 
    go install github.com/ffuf/ffuf@latest  
    go install github.com/OJ/gobuster/v3@latest  
    go install github.com/mrco24/mrco24-lfi@latest  
    go install github.com/mrco24/open-redirect@latest  
    go install -v github.com/projectdiscovery/interactsh/cmd/interactsh-client  
    go install -v github.com/hahwul/dalfox/v2@latest 
    go install github.com/Emoe/kxss@late  
    go install github.com/KathanP19/Gxss@latest  
    go install github.com/ethicalhackingplayground/bxss@latest 
    go install github.com/ferreiraklet/Jeeves@latest 
    go install github.com/mrco24/time-sql@latest  
    go install github.com/mrco24/mrco24-error-sql@latest 
    go install -v github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest 
    go install -v github.com/xm1k3/cent@latest  
    go install github.com/MrEmpy/mantra@latest 
    go install -v github.com/projectdiscovery/notify/cmd/notify@latest 
    go install github.com/mrco24/tok@latest 
    go install github.com/tomnomnom/hacks/anti-burl@latest  
    go install github.com/tomnomnom/unfurl@latest 
    go install github.com/tomnomnom/fff@latest 
    go install github.com/tomnomnom/gron@latest 
    go install github.com/tomnomnom/qsreplace@latest  
    go install github.com/dwisiswant0/cf-check@latest  
    
    echo -e ${GR}"Go Tools Done..."${NL};
    echo -e ${BL}"Installed Tools: subfinder, anew, assetfinder, katana, waybackurls, hakrawler, puredns, dnsx, gau, socialhunter, subzy, getJS, shuffledns, github-subdomains, amass, crobat, mapcidr, chaos, gotator, cero, galer, quickcert, gowitness, httpx, httprobe, gospider, parameters, gf, otx-url, ffuf, gobuster, mrco24-lfi, open-redirect, interactsh-client, dalfox, kxss, Gxss, bxss, Jeeves, time-sql, error-sql, nuclei, cent, mantra, notify, tok, anti-burl, unfurl, fff, gron, qsreplace, cf-check."${NL};
}

PYTHONSETUP(){
	echo -e ${GR}Python installation...${NL}
	sudo apt install python3 python3-pip -y
	sudo apt install python3-venv -y
	sudo apt install build-essential libssl-dev libffi-dev python3-dev -y
	sudo apt install python2
}

PYTHONTOOLS(){
	pip3 install arjun 
	pip3 install jsbeautifier 
	pip3 install lxml 
	pip3 install GitHacker 
	pip3 install uro
	pip3 install contextvars
	pip3 install urless
	git clone https://github.com/0xRyuk/crtsh.git /tmp/crtsh && cd /tmp/crtsh
	pip3 install -r /tmp/crtsh/requirments.txt
	sudo mkdir -p /opt/crtsh
	sudo cp /tmp/crtsh/crtsh.py /opt/crtsh/
	sudo echo 'alias crtsh="python3 /opt/crtsh/crtsh.py"'>>~/.bashrc
	git clone https://github.com/m4ll0k/SecretFinder.git /tmp/secretfinder && cd /tmp/secretfinder
	pip install -r /tmp/secretfinder/requirements.txt
	sudo mkdir -p /opt/secretfinder
	sudo cp /tmp/secretfinder/SecretFinder.py  /opt/secretfinder/secretfinder.py
	sudo echo 'alias secretfinder="python3 /opt/secretfinder/secretfinder.py"'>> ~/.bashrc
	git clone https://github.com/GerbenJavado/LinkFinder.git /tmp/linkfinder && cd /tmp/linkfinder
	sudo mkdir -p /opt/linkfinder
	sudo cp linkfinder.py /opt/linkfinder/linkfinder.py
	sudo echo 'alias linkfinder="python3 /opt/linkfinder/linkfinder.py"'>>~/.bashrc
	. ~/.bashrc & source ~/.bashrc
}
KALI-TOOLS(){
	echo -e "Adding" ${GR}Kali Linux${NL} "Repository"
	apt-key adv --keyserver keyserver.ubuntu.com --recv-keys ED444FF07D8D0BF6
	echo -e '# Kali linux repositories | Added by Bounty-VPS\ndeb http://http.kali.org/kali kali-rolling main contribnon-free' >> /etc/apt/sources.list
	sudo apt update -y && sudo apt full-upgrade -y
	sudo apt autoremove -y
	sudo apt install --fix-broken -y
	echo ""
	echo -e "Downloading" ${GR}Kali Linux${NL} "Tools"
	sudo apt-get install kali-menu
	sudo apt-get -f install acccheck ace-voip amap automater braa casefile cdpsnarf cisco-torch cookie-cadger copy-router-config dmitry dnmap dnsenum dnsmap dnsrecon dnstracer dnswalk dotdotpwn enum4linux enumiax exploitdb fierce firewalk fragroute fragrouter ghost-phisher golismero goofile lbd maltego-teeth masscan metagoofil miranda nmap p0f parsero recon-ng set smtp-user-enum snmpcheck sslcaudit sslsplit sslstrip sslyze thc-ipv6 theharvester tlssled twofi urlcrazy wireshark wol-e xplico ismtp intrace hping3 bbqsql bed cisco-auditing-tool cisco-global-exploiter cisco-ocs cisco-torch copy-router-config doona dotdotpwn greenbone-security-assistant hexorbase jsql lynis nmap ohrwurm openvas-cli openvas-manager openvas-scanner oscanner powerfuzzer sfuzz sidguesser siparmyknife sqlmap sqlninja sqlsus thc-ipv6 tnscmd10g unix-privesc-check yersinia aircrack-ng asleap bluelog blueranger bluesnarfer bully cowpatty crackle eapmd5pass fern-wifi-cracker ghost-phisher giskismet gqrx kalibrate-rtl killerbee kismet mdk3 mfcuk mfoc mfterm multimon-ng pixiewps reaver redfang spooftooph wifi-honey wifitap wifite apache-users arachni bbqsql blindelephant burpsuite cutycapt davtest deblaze dirb dirbuster fimap funkload grabber jboss-autopwn joomscan jsql maltego-teeth padbuster paros parsero plecost powerfuzzer proxystrike recon-ng skipfish sqlmap sqlninja sqlsus ua-tester uniscan vega w3af webscarab websploit wfuzz wpscan xsser zaproxy burpsuite dnschef fiked hamster-sidejack hexinject iaxflood inviteflood ismtp mitmproxy ohrwurm protos-sip rebind responder rtpbreak rtpinsertsound rtpmixsound sctpscan siparmyknife sipp sipvicious sniffjoke sslsplit sslstrip thc-ipv6 voiphopper webscarab wifi-honey wireshark xspy yersinia zaproxy cryptcat cymothoa dbd dns2tcp http-tunnel httptunnel intersect nishang polenum powersploit pwnat ridenum sbd u3-pwn webshells weevely casefile cutycapt dos2unix dradis keepnote magictree metagoofil nipper-ng pipal armitage backdoor-factory cisco-auditing-tool cisco-global-exploiter cisco-ocs cisco-torch crackle jboss-autopwn linux-exploit-suggester maltego-teeth set shellnoob sqlmap thc-ipv6 yersinia beef-xss binwalk bulk-extractor chntpw cuckoo dc3dd ddrescue dumpzilla extundelete foremost galleta guymager iphone-backup-analyzer p0f pdf-parser pdfid pdgmail peepdf volatility xplico dhcpig funkload iaxflood inviteflood ipv6-toolkit mdk3 reaver rtpflood slowhttptest t50 termineter thc-ipv6 thc-ssl-dos acccheck cewl chntpw cisco-auditing-tool cmospwd creddump crunch findmyhash gpp-decrypt hash-identifier hexorbase john johnny keimpx maltego-teeth maskprocessor multiforcer ncrack oclgausscrack pack patator polenum rainbowcrack rcracki-mt rsmangler statsprocessor thc-pptp-bruter truecrack webscarab wordlists zaproxy apktool dex2jar python-distorm3 edb-debugger jad javasnoop jd ollydbg smali valgrind yara android-sdk apktool arduino dex2jar sakis3g smali 

	cd /tmp && wget http://www.morningstarsecurity.com/downloads/bing-ip2hosts-0.4.tar.gz && tar -xzvf bing-ip2hosts-0.4.tar.gz && sudo cp bing-ip2hosts-0.4/bing-ip2hosts /usr/local/bin/

}

GOSETUP && GOTOOLS && PYTHONSETUP && PYTHONTOOLS && KALI-TOOLS;
. ~/.bashrc & source ~/.bashrc

echo -e "\n"
echo -e "\n"

echo -e "Congrats! Your VPS is ready to H4ck Th3 Pl4n3t\nHit a follow button ${GR}@sudosuraj${NL} on LinkedIn, Github, Instagram\nCreated With ❤️ in India."
