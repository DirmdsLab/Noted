# Minecraft Server Setup on Termux

This guide explains how to set up a Minecraft server on Termux that allows Java Edition and Bedrock Edition players to join and play together in the same world.

The same setup can also be used on Docker, Podman, VPS servers

## Download Paper

Download the latest Paper server from:

[https://papermc.io/downloads/paper](https://papermc.io/downloads/paper)

Example downloaded file:

```text
paper-26.2-84.jar
```

The filename will vary depending on the Paper version.

Rename the downloaded file to:

```text
paper.jar
```

Create a server directory:

```text
Minecraft-server
```

Move `paper.jar` into the `Minecraft-server` folder.

## Install Java

Update Termux packages: (pkg or apt)

```bash
pkg update && pkg upgrade
```

Install Java:

```bash
pkg install openjdk-25
```

Use the Java version recommended by the Paper documentation:

[https://docs.papermc.io/paper/getting-started/](https://docs.papermc.io/paper/getting-started/)

## Start the Server

Run the server for the first time:

```bash
java -Xms1G -Xmx1G -jar paper.jar --nogui
```

Adjust the memory allocation as needed.

Examples:

* `1G` = 1 GB RAM
* `512M` = 512 MB RAM

On the first startup, the server will stop with this message:

```text
Failed to load eula.txt
```

Accept the Minecraft EULA by running:

```bash
sed -i 's/eula=false/eula=true/' eula.txt
```

Or edit the file manually using:

```bash
nano eula.txt
```

---

# Enable Java and Bedrock Cross-Play

Install the Geyser plugin.

Download:

[https://geysermc.org/download](https://geysermc.org/download)

Choose the **Paper** version.

Example file:

```text
Geyser-Spigot.jar
```

Place the file inside the `plugins` folder.

Start the server once until it finishes loading, then stop it.

---

# Install Floodgate

Floodgate allows Bedrock players to join without owning a Java Edition account.

Documentation:

[https://geysermc.org/wiki/floodgate/setup/](https://geysermc.org/wiki/floodgate/setup/)

Download the **Paper** version.

Example file:

```text
floodgate-spigot.jar
```

Place it in the `plugins` folder.

Edit:

```text
plugins/Geyser-Spigot/config.yml
```

Change:

```yaml
auth-type: online
```

to:

```yaml
auth-type: floodgate
```

Also edit:

```text
server.properties
```

Change:

```properties
online-mode=true
```

to:

```properties
online-mode=false
```

---

# Support Multiple Java Versions

To allow multiple Java Edition versions to join the server, install ViaVersion and ViaBackwards.

This only applies to Java Edition.

Bedrock Edition players should use the latest version because Bedrock clients are generally required to stay updated.

Check compatibility:

[https://viaversion.com/setup.html?lang=en](https://viaversion.com/setup.html?lang=en)

Example:

Allow Minecraft **1.21 and newer** to join.

The compatibility page will recommend:

```text
You need ViaVersion + ViaBackwards
```

and the following configuration:

```yaml
block-versions: ["<1.21"]
```

Download the required plugins:

[https://viaversion.com/](https://viaversion.com/)

Example files:

```text
ViaVersion-5.11.1-SNAPSHOT.jar
ViaBackwards-5.11.1-SNAPSHOT.jar
```

Place both files into the `plugins` folder.

Start the server, wait until it finishes loading, then stop it.

Edit:

```text
plugins/ViaVersion/config.yml
```

Change:

```yaml
block-versions: []
```

to:

```yaml
block-versions: ["<1.21"]
```

---

# Server Ports

Java Edition:

```properties
server.properties

server-port=25565
```

Bedrock Edition:

```text
plugins/Geyser-Spigot/config.yml
```

```yaml
port: 19132
```

Start the server again after making the changes.

---

# Adding More Plugins

Additional plugins can be installed by placing their `.jar` files into the `plugins` folder.

Restart the server after adding new plugins.

---

# Make the Server Public

To allow players outside your local network to connect, you can use:

* Playit.gg (free)
* Port forwarding (requires a public IP or hosting provider support)

For Playit.gg on Termux, install Ubuntu using `proot-distro` and follow the installation instructions from the official Playit.gg website.