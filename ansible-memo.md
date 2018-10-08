1. ssh connection persistance

 ~/.ssh/config

Host * 
  Compression yes 
  ServerAliveInterval 60 
  ServerAliveCountMax 5 
  ControlMaster auto 
  ControlPath ~/.ssh/sockets/%r@%h-%p
  ControlPersist 4h


2. time elapse calculation

mkdir callback_plugins 
cd callback_plugins 
wget https://raw.githubusercontent.com/jlafon/ansible-profile/master/callback_plugins/profile_tasks.py

(
after download,  change /etc/ansible/ansible.cfg to add

# enable callback plugins, they can output to stdout but cannot be 'stdout' type.
#callback_whitelist = timer, mail
callback_whitelist = timer, profile_tasks

)
