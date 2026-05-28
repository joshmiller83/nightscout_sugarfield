# Nightscout — ns-sf.joshnliz.com

Personal CGM monitor running Nightscout v15 on GCP free tier.

**URL:** https://ns-sf.joshnliz.com  
**API Secret:** stored in `/opt/nightscout/.env` on the VM (ask Josh)

---

## Architecture

```
Browser → Cloudflare (HTTPS) → GCP e2-micro VM (nginx:80 → PM2 → Nightscout:1337) → MongoDB Atlas
```

| Layer | Service | Role |
|---|---|---|
| DNS + HTTPS | Cloudflare (free) | Terminates SSL, proxies traffic to VM |
| App server | GCP Compute Engine e2-micro (free tier) | Runs nginx + Nightscout Node.js app |
| Process manager | PM2 | Keeps Nightscout running, auto-restarts on crash or VM reboot |
| Database | MongoDB Atlas M0 (free, 512MB) | Stores all CGM readings, treatments, profiles |
| CI/CD | GitHub Actions | SSH deploys to VM on push to `main` |

---

## What Each Service Does

### Cloudflare
- **DNS:** `ns-sf.joshnliz.com` A record → `34.60.64.89` (VM external IP), proxied (orange cloud)
- **HTTPS:** Cloudflare provides the SSL cert to browsers. SSL mode is **Flexible** — Cloudflare speaks HTTPS to the browser, plain HTTP to the VM on port 80.
- **What to watch:** If the site shows a Cloudflare error page (521, 522, 524), the VM or nginx is down. If you see a security warning in the browser, the proxy may have been toggled off.
- **Console:** https://dash.cloudflare.com → joshnliz.com → DNS / SSL/TLS

### GCP (Google Cloud Platform)
- **Project:** `nightscout-sugarfield`
- **VM:** `nightscout-vm`, zone `us-central1-a`, machine type `e2-micro` (always free tier)
- **OS:** Ubuntu 22.04 LTS
- **Disk:** 30GB standard (always free tier)
- **What to watch:** GCP will email `mill4433.purdue@gmail.com` if billing spikes (shouldn't happen on free tier). The VM can be restarted from the console if it becomes unresponsive.
- **Console:** https://console.cloud.google.com/compute/instances?project=nightscout-sugarfield
- **SSH into VM:**
  ```bash
  /opt/homebrew/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/bin/gcloud compute ssh nightscout-vm \
    --zone=us-central1-a --project=nightscout-sugarfield --tunnel-through-iap
  ```

### MongoDB Atlas
- **Cluster:** `nightscout.rfa5hdp.mongodb.net`, M0 free tier (512MB)
- **Database user:** `nightscout_db_user`
- **Network access:** VM IP `34.60.64.89` is whitelisted
- **What to watch:** Atlas sends email when storage approaches 512MB (~3 months of typical CGM data). At that point, either prune old entries or upgrade to M2 ($9/mo, 2GB).
- **Console:** https://cloud.mongodb.com

### GitHub Actions
- **Repo:** https://github.com/joshmiller83/nightscout_sugarfield
- **Trigger:** Push to `main` branch → SSH into VM → `git pull` nightscout upstream → `npm ci` if changed → `pm2 restart`
- **Secrets stored:** `GCP_SSH_PRIVATE_KEY`, `GCP_VM_IP`, `GCP_VM_USER`
- **What to watch:** A failed Actions run (red ✗) means the deploy didn't apply. The site keeps running on the last good version — it won't go down, but your update didn't land.

---

## Keeping It Up-to-Date

### Nightscout app updates
Nightscout releases new versions at https://github.com/nightscout/cgm-remote-monitor/releases.

To update, SSH into the VM and run:
```bash
cd /opt/nightscout
git pull origin master
npm ci --omit=optional
pm2 restart nightscout
pm2 save
```

Or just push any commit to `main` in this repo — GitHub Actions runs the same steps automatically.

### OS security patches (monthly is fine)
```bash
# SSH into VM, then:
sudo apt-get update && sudo apt-get upgrade -y
sudo reboot   # PM2 will auto-restart Nightscout after reboot
```

### Checking Nightscout is healthy
```bash
# On the VM:
pm2 status              # should show "online", not "errored"
pm2 logs nightscout --lines 50   # look for connection errors
curl -s http://localhost:1337/api/v1/status.json | python3 -m json.tool
```

Or just hit https://ns-sf.joshnliz.com/api/v1/status.json in a browser.

### If Nightscout crashes and won't restart
```bash
pm2 logs nightscout --lines 100   # find the error
pm2 restart nightscout            # try a restart
# If that fails:
pm2 delete nightscout
cd /opt/nightscout && pm2 start lib/server/server.js --name nightscout
pm2 save
```

### Rotating the API secret
Edit `/opt/nightscout/.env` on the VM, change `API_SECRET`, then `pm2 restart nightscout`. Update your CGM uploader app with the new secret.

---

## Local Files Reference

| File | Purpose |
|---|---|
| `scripts/provision-gcp.sh` | One-time script to create the GCP project + VM (already run) |
| `scripts/setup-vm.sh` | One-time VM provisioning (installs Node, PM2, nginx, clones nightscout) |
| `scripts/complete-setup.sh` | Used to recover from the OOM-killed first run |
| `nginx/nightscout.conf` | nginx reverse proxy config (reference copy — live version is on VM) |
| `ecosystem.config.js` | PM2 config reference |
| `.env.example` | Template showing required environment variables |
| `.github/workflows/deploy.yml` | GitHub Actions deploy workflow |

### Secrets and credentials (NOT in this repo)
| What | Where |
|---|---|
| Cloudflare API token | `~/.config/nightscout/cloudflare.ini` (local machine, permissions 600) |
| SSH deploy private key | `nightscout-deploy` (local, in `.gitignore`) |
| SSH deploy public key | `nightscout-deploy.pub` (local, also in GCP instance metadata) |
| Nightscout `.env` (MongoDB URI, API secret) | `/opt/nightscout/.env` on the VM only (permissions 600) |

---

## Free Tier Limits to Know

| Service | Limit | Risk |
|---|---|---|
| GCP e2-micro | 1 instance in us-central1 free forever | Don't create a second VM in the same region or it starts billing |
| GCP disk | 30GB standard free | Currently using ~10GB; safe |
| MongoDB M0 | 512MB storage | Monitor in Atlas dashboard; ~3 months of CGM data |
| Cloudflare free | Unlimited requests | No meaningful limit for personal use |
