### Install btrfs
```bash
curl -fsSL https://raw.githubusercontent.com/Cyber-Zhaba/handy-scripts/refs/heads/master/install-btrfs.sh | bash -s -- -d /dev/mapper/root -b /dev/nvme0n1p5 -f
```

### Mirrorlist optimizer
```bash
curl -fsSL https://raw.githubusercontent.com/Cyber-Zhaba/handy-scripts/refs/heads/master/mirrorlist-optimizer.sh | bash
```

### Essential packages
```bash
curl -fsSL https://raw.githubusercontent.com/Cyber-Zhaba/handy-scripts/refs/heads/master/essential-packages.sh | bash
```


```bash
curl -fsSL https://raw.githubusercontent.com/Cyber-Zhaba/handy-scripts/refs/heads/master/archiso-packages.sh | bash
```

### After chroot
```bash
curl -fsSL https://raw.githubusercontent.com/Cyber-Zhaba/handy-scripts/refs/heads/master/after-chroot.sh > ./after-chroot.sh && chmod +x after-chroot.sh && ./after-chroot.sh
```

```bash
sh <(curl --proto '=https' --tlsv1.2 -L https://nixos.org/nix/install) --daemon

curl -LsSf https://astral.sh/uv/install.sh | sh

curl -fsSL https://opencode.ai/install | bash
```

