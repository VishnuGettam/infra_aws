#!/bin/bash
# =============================================================================
#  deploy_apache_metadata.sh
#  Installs Apache (httpd) on Amazon Linux 2 / Amazon Linux 2023, pulls EC2
#  instance metadata using IMDSv2 (token-based), and renders a styled
#  dashboard at /var/www/html/index.html.
#
#  Usage:
#    - As EC2 User Data: paste the whole file (runs as root at first boot)
#    - Manually:         sudo bash deploy_apache_metadata.sh
# =============================================================================
set -uo pipefail

LOG=/var/log/deploy_apache_metadata.log
exec > >(tee -a "$LOG") 2>&1
echo "==== $(date -Is) : starting deployment ===="

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (sudo)." >&2
  exit 1
fi

# -----------------------------------------------------------------------------
# 1. Install & start Apache
# -----------------------------------------------------------------------------
if command -v dnf >/dev/null 2>&1; then
  PKG=dnf      # Amazon Linux 2023
else
  PKG=yum      # Amazon Linux 2
fi
$PKG -y update
$PKG -y install httpd
systemctl enable --now httpd

# -----------------------------------------------------------------------------
# 2. IMDSv2 token (retry – IMDS can be slow right after boot)
# -----------------------------------------------------------------------------
IMDS=http://169.254.169.254
TOKEN=""
for i in {1..10}; do
  TOKEN=$(curl -sf -X PUT "$IMDS/latest/api/token" \
            -H "X-aws-ec2-metadata-token-ttl-seconds: 21600") && [[ -n "$TOKEN" ]] && break
  echo "IMDSv2 token attempt $i failed, retrying..."
  sleep 3
done
if [[ -z "$TOKEN" ]]; then
  echo "ERROR: could not obtain IMDSv2 token. Check the instance metadata options (HttpEndpoint=enabled)." >&2
  exit 1
fi

# meta <path>  -> value or "N/A"
meta() {
  local v
  v=$(curl -sf -H "X-aws-ec2-metadata-token: $TOKEN" "$IMDS/latest/meta-data/$1" 2>/dev/null) || v=""
  echo "${v:-N/A}"
}

# -----------------------------------------------------------------------------
# 3. Collect metadata
# -----------------------------------------------------------------------------
INSTANCE_ID=$(meta instance-id)
INSTANCE_TYPE=$(meta instance-type)
AMI_ID=$(meta ami-id)
NAME_TAG=$(meta tags/instance/Name)          # only works if "tags in metadata" is enabled
LIFECYCLE=$(meta instance-life-cycle)
ACCOUNT_ID=$(curl -sf -H "X-aws-ec2-metadata-token: $TOKEN" \
               "$IMDS/latest/dynamic/instance-identity/document" | \
               grep -oP '"accountId"\s*:\s*"\K[0-9]+' || true)
ACCOUNT_ID=${ACCOUNT_ID:-N/A}

REGION=$(meta placement/region)
AZ=$(meta placement/availability-zone)
AZ_ID=$(meta placement/availability-zone-id)

HOSTNAME_LOCAL=$(meta local-hostname)
PRIVATE_IP=$(meta local-ipv4)
PUBLIC_IP=$(meta public-ipv4)
PUBLIC_DNS=$(meta public-hostname)
MAC=$(meta mac)
if [[ "$MAC" != "N/A" ]]; then
  VPC_ID=$(meta "network/interfaces/macs/$MAC/vpc-id")
  SUBNET_ID=$(meta "network/interfaces/macs/$MAC/subnet-id")
  VPC_CIDR=$(meta "network/interfaces/macs/$MAC/vpc-ipv4-cidr-block")
  SUBNET_CIDR=$(meta "network/interfaces/macs/$MAC/subnet-ipv4-cidr-block")
else
  VPC_ID=N/A; SUBNET_ID=N/A; VPC_CIDR=N/A; SUBNET_CIDR=N/A
fi
SECURITY_GROUPS=$(meta security-groups | paste -sd ',' - | sed 's/,/, /g')
IAM_ROLE=$(meta iam/security-credentials/ | head -n1)

OS_NAME=$(. /etc/os-release && echo "$PRETTY_NAME")
KERNEL=$(uname -r)
ARCH=$(uname -m)
CPUS=$(nproc)
MEM=$(free -h | awk '/^Mem:/ {print $2}')
DISK=$(df -h / | awk 'NR==2 {print $2" total, "$4" free"}')
HTTPD_VER=$(httpd -v | awk -F'[ /]' '/Server version/ {print $4}')
DEPLOYED_AT=$(date -u '+%Y-%m-%d %H:%M:%S UTC')

DISPLAY_NAME="$NAME_TAG"
[[ "$DISPLAY_NAME" == "N/A" ]] && DISPLAY_NAME="$INSTANCE_ID"

# -----------------------------------------------------------------------------
# 4. Render index.html
#    (unquoted heredoc so shell variables expand – no backticks or ${} in JS)
# -----------------------------------------------------------------------------
cat > /var/www/html/index.html <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>$DISPLAY_NAME · EC2 Instance</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
<style>
  :root {
    --bg: #0b1020;
    --card: rgba(255,255,255,0.05);
    --border: rgba(255,255,255,0.09);
    --text: #e6e9f2;
    --muted: #8b93a7;
    --accent: #ff9900;
    --accent2: #7c5cff;
    --ok: #22c55e;
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    font-family: 'Inter', system-ui, sans-serif;
    color: var(--text);
    background: var(--bg);
    min-height: 100vh;
    overflow-x: hidden;
  }
  /* animated background blobs */
  .bg { position: fixed; inset: 0; z-index: -1; overflow: hidden; }
  .blob { position: absolute; border-radius: 50%; filter: blur(90px); opacity: .45; animation: float 18s ease-in-out infinite; }
  .b1 { width: 520px; height: 520px; background: #ff9900; top: -160px; left: -120px; }
  .b2 { width: 480px; height: 480px; background: #7c5cff; bottom: -160px; right: -100px; animation-delay: -6s; }
  .b3 { width: 360px; height: 360px; background: #06b6d4; top: 40%; left: 55%; animation-delay: -12s; opacity: .25; }
  @keyframes float { 0%,100% { transform: translate(0,0) scale(1); } 50% { transform: translate(40px,-30px) scale(1.08); } }

  .wrap { max-width: 1200px; margin: 0 auto; padding: 48px 20px 64px; }

  header { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: 20px; margin-bottom: 36px; }
  .brand { display: flex; align-items: center; gap: 16px; }
  .logo {
    width: 56px; height: 56px; border-radius: 16px;
    background: linear-gradient(135deg, var(--accent), #ffb84d);
    display: grid; place-items: center; font-weight: 800; color: #111; font-size: 20px;
    box-shadow: 0 10px 30px rgba(255,153,0,.35);
  }
  .eyebrow { color: var(--muted); font-size: 13px; letter-spacing: .14em; text-transform: uppercase; font-weight: 600; }
  h1 { font-size: clamp(24px, 4vw, 36px); font-weight: 800; letter-spacing: -.02em;
       background: linear-gradient(90deg, #fff, #c7cbe0); -webkit-background-clip: text; background-clip: text; color: transparent; }
  .status { display: flex; gap: 10px; flex-wrap: wrap; }
  .pill {
    display: inline-flex; align-items: center; gap: 8px; padding: 8px 14px; border-radius: 999px;
    background: var(--card); border: 1px solid var(--border); font-size: 13px; font-weight: 500; backdrop-filter: blur(10px);
  }
  .dot { width: 8px; height: 8px; border-radius: 50%; background: var(--ok); box-shadow: 0 0 0 0 rgba(34,197,94,.7); animation: pulse 2s infinite; }
  @keyframes pulse { 70% { box-shadow: 0 0 0 10px rgba(34,197,94,0); } 100% { box-shadow: 0 0 0 0 rgba(34,197,94,0); } }

  .hero { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 16px; margin-bottom: 28px; }
  .stat {
    padding: 20px; border-radius: 18px; background: var(--card); border: 1px solid var(--border);
    backdrop-filter: blur(14px); position: relative; overflow: hidden;
  }
  .stat::after { content: ""; position: absolute; inset: 0 0 auto 0; height: 3px; background: linear-gradient(90deg, var(--accent), var(--accent2)); }
  .stat .k { color: var(--muted); font-size: 12px; text-transform: uppercase; letter-spacing: .1em; font-weight: 600; }
  .stat .v { font-size: 22px; font-weight: 700; margin-top: 8px; word-break: break-all; }

  .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(340px, 1fr)); gap: 20px; }
  .card {
    background: var(--card); border: 1px solid var(--border); border-radius: 20px; padding: 24px;
    backdrop-filter: blur(14px); transition: transform .25s, border-color .25s;
    animation: rise .6s ease both;
  }
  .card:hover { transform: translateY(-4px); border-color: rgba(255,153,0,.4); }
  .card:nth-child(2) { animation-delay: .08s; } .card:nth-child(3) { animation-delay: .16s; } .card:nth-child(4) { animation-delay: .24s; }
  @keyframes rise { from { opacity: 0; transform: translateY(16px); } to { opacity: 1; transform: none; } }
  .card h2 { font-size: 15px; font-weight: 700; display: flex; align-items: center; gap: 10px; margin-bottom: 16px; }
  .card h2 .ic { width: 30px; height: 30px; border-radius: 9px; display: grid; place-items: center; font-size: 15px; background: rgba(255,255,255,.07); }

  .row { display: flex; justify-content: space-between; align-items: center; gap: 12px; padding: 11px 0; border-top: 1px solid var(--border); }
  .row:first-of-type { border-top: none; }
  .row .k { color: var(--muted); font-size: 13px; white-space: nowrap; }
  .row .v { font-family: 'JetBrains Mono', monospace; font-size: 13px; text-align: right; word-break: break-all; display: flex; align-items: center; gap: 8px; }
  .copy {
    border: 1px solid var(--border); background: transparent; color: var(--muted); cursor: pointer;
    border-radius: 7px; padding: 3px 7px; font-size: 11px; opacity: 0; transition: opacity .2s, color .2s;
  }
  .row:hover .copy { opacity: 1; }
  .copy:hover { color: var(--accent); border-color: var(--accent); }
  .na { color: #5b6275; font-style: italic; }

  footer { margin-top: 40px; text-align: center; color: var(--muted); font-size: 13px; line-height: 1.8; }
  footer code { font-family: 'JetBrains Mono', monospace; color: var(--text); }
  .toast { position: fixed; bottom: 24px; left: 50%; transform: translateX(-50%) translateY(80px);
           background: #111827; border: 1px solid var(--border); padding: 10px 18px; border-radius: 10px; font-size: 13px; transition: transform .3s; }
  .toast.show { transform: translateX(-50%) translateY(0); }
  @media (max-width: 420px) { .grid { grid-template-columns: 1fr; } .row { flex-direction: column; align-items: flex-start; } .row .v { text-align: left; } }
</style>
</head>
<body>
<div class="bg"><div class="blob b1"></div><div class="blob b2"></div><div class="blob b3"></div></div>

<div class="wrap">
  <header>
    <div class="brand">
      <div class="logo">EC2</div>
      <div>
        <div class="eyebrow">Apache $HTTPD_VER · Amazon EC2</div>
        <h1>$DISPLAY_NAME</h1>
      </div>
    </div>
    <div class="status">
      <span class="pill"><span class="dot"></span> Server Online</span>
      <span class="pill">🔐 IMDSv2</span>
      <span class="pill" id="clock">--:--:--</span>
    </div>
  </header>

  <section class="hero">
    <div class="stat"><div class="k">Instance Type</div><div class="v">$INSTANCE_TYPE</div></div>
    <div class="stat"><div class="k">Region</div><div class="v">$REGION</div></div>
    <div class="stat"><div class="k">Availability Zone</div><div class="v">$AZ</div></div>
    <div class="stat"><div class="k">Public IP</div><div class="v">$PUBLIC_IP</div></div>
  </section>

  <section class="grid">
    <div class="card">
      <h2><span class="ic">🖥️</span> Instance</h2>
      <div class="row"><span class="k">Instance ID</span><span class="v">$INSTANCE_ID</span></div>
      <div class="row"><span class="k">Name Tag</span><span class="v">$NAME_TAG</span></div>
      <div class="row"><span class="k">Instance Type</span><span class="v">$INSTANCE_TYPE</span></div>
      <div class="row"><span class="k">AMI ID</span><span class="v">$AMI_ID</span></div>
      <div class="row"><span class="k">Lifecycle</span><span class="v">$LIFECYCLE</span></div>
      <div class="row"><span class="k">Account ID</span><span class="v">$ACCOUNT_ID</span></div>
      <div class="row"><span class="k">IAM Role</span><span class="v">$IAM_ROLE</span></div>
    </div>

    <div class="card">
      <h2><span class="ic">🌐</span> Network</h2>
      <div class="row"><span class="k">Private IP</span><span class="v">$PRIVATE_IP</span></div>
      <div class="row"><span class="k">Public IP</span><span class="v">$PUBLIC_IP</span></div>
      <div class="row"><span class="k">Private DNS</span><span class="v">$HOSTNAME_LOCAL</span></div>
      <div class="row"><span class="k">Public DNS</span><span class="v">$PUBLIC_DNS</span></div>
      <div class="row"><span class="k">MAC Address</span><span class="v">$MAC</span></div>
      <div class="row"><span class="k">Security Groups</span><span class="v">$SECURITY_GROUPS</span></div>
    </div>

    <div class="card">
      <h2><span class="ic">📍</span> Placement &amp; VPC</h2>
      <div class="row"><span class="k">Region</span><span class="v">$REGION</span></div>
      <div class="row"><span class="k">Availability Zone</span><span class="v">$AZ</span></div>
      <div class="row"><span class="k">AZ ID</span><span class="v">$AZ_ID</span></div>
      <div class="row"><span class="k">VPC ID</span><span class="v">$VPC_ID</span></div>
      <div class="row"><span class="k">VPC CIDR</span><span class="v">$VPC_CIDR</span></div>
      <div class="row"><span class="k">Subnet ID</span><span class="v">$SUBNET_ID</span></div>
      <div class="row"><span class="k">Subnet CIDR</span><span class="v">$SUBNET_CIDR</span></div>
    </div>

    <div class="card">
      <h2><span class="ic">⚙️</span> System</h2>
      <div class="row"><span class="k">Operating System</span><span class="v">$OS_NAME</span></div>
      <div class="row"><span class="k">Kernel</span><span class="v">$KERNEL</span></div>
      <div class="row"><span class="k">Architecture</span><span class="v">$ARCH</span></div>
      <div class="row"><span class="k">vCPUs</span><span class="v">$CPUS</span></div>
      <div class="row"><span class="k">Memory</span><span class="v">$MEM</span></div>
      <div class="row"><span class="k">Root Disk</span><span class="v">$DISK</span></div>
      <div class="row"><span class="k">Apache Version</span><span class="v">$HTTPD_VER</span></div>
    </div>
  </section>

  <footer>
    Metadata captured via IMDSv2 at <code>$DEPLOYED_AT</code><br>
    Re-run the deploy script to refresh values.
  </footer>
</div>

<div class="toast" id="toast">Copied to clipboard</div>

<script>
  // live clock
  function tick() { document.getElementById('clock').textContent = '🕒 ' + new Date().toLocaleTimeString(); }
  tick(); setInterval(tick, 1000);

  // dim N/A values and add copy buttons
  document.querySelectorAll('.row .v').forEach(function (el) {
    var val = el.textContent.trim();
    if (val === 'N/A' || val === '') { el.innerHTML = '<span class="na">not available</span>'; return; }
    var btn = document.createElement('button');
    btn.className = 'copy'; btn.textContent = 'copy';
    btn.onclick = function () {
      var t = document.createElement('textarea'); t.value = val; document.body.appendChild(t);
      t.select(); document.execCommand('copy'); document.body.removeChild(t);
      var toast = document.getElementById('toast'); toast.classList.add('show');
      setTimeout(function () { toast.classList.remove('show'); }, 1400);
    };
    el.appendChild(btn);
  });
</script>
</body>
</html>
EOF

chown apache:apache /var/www/html/index.html
chmod 644 /var/www/html/index.html
systemctl restart httpd

echo "==== $(date -Is) : deployment complete ===="
echo "Open: http://$PUBLIC_IP/  (instance: $INSTANCE_ID)"