#cloud-config 
# set timezone to Asia/Shanghai
timezone: Asia/Shanghai

# package_update: true
# package_upgrade: false
# packages:
#   - iptables
#   - iptables-persistent
#   - netfilter-persistent
#   - curl
#   - jq
#   - net-tools
#   - iputils-ping
#   - traceroute
#   - tcpdump
#   - stress
#   - podman
#   - podman-docker

write_files:
  - path: /etc/containers/nodocker
    owner: root:root
    permissions: '0644'
    content: |
      # keep this file existing for podman-docker to work without message
  
  - path: /etc/container.env
    owner: root:root
    permissions: '0644'
    content: |
      APP_NAME=upload-server
      APP_IMAGE=${upload_server_container_url}
      REGION_NAME=${region_name}
      REGION_SHORT_NAME=${region_short_name}
      SPRING_PROFILES_ACTIVE=az${region_short_name}
  
  - path: /usr/local/bin/image-pull.sh
    owner: root:root
    permissions: '0755'
    content: |
      #!/bin/bash
      ACR_RESOURCE_ID=${acr_resource_id}
      ACR_NAME=$(basename $ACR_RESOURCE_ID)
      APP_IMAGE=${upload_server_container_url}

      az login --identity
      az acr login --name $ACR_NAME
      podman pull $APP_IMAGE


  - path: /etc/systemd/system/podman-upload-server.service
    owner: root:root
    permissions: '0644'
    content: |
      [Unit]
      Description=Podman upload-server.service
      Documentation=man:podman-generate-systemd(1)
      Wants=network-online.target
      After=network-online.target
      RequiresMountsFor=%t/containers
      
      [Service]
      Environment=PODMAN_SYSTEMD_UNIT=%n
      EnvironmentFile=/etc/container.env
      LimitNOFILE=655350
      LimitNPROC=655350
      Restart=always
      RestartSec=2
      TimeoutStopSec=630
      ExecStartPre=/bin/rm -f %t/%n.ctr-id
      ExecStartPre=/usr/local/bin/image-pull.sh
      ExecStart=/usr/bin/podman run --cidfile=%t/%n.ctr-id --cgroups=no-conmon --rm --sdnotify=conmon --replace -d --network=host --hostname=%H --env-file=/etc/container.env --name $APP_NAME $APP_IMAGE
      ExecStop=/usr/bin/podman stop --ignore --cidfile=%t/%n.ctr-id
      ExecStopPost=/usr/bin/podman rm -f --ignore --cidfile=%t/%n.ctr-id      
      Type=notify
      NotifyAccess=all
      
      [Install]
      WantedBy=multi-user.target

  - path: /usr/local/bin/termination-listener.sh
    owner: root:root
    permissions: '0755'
    content: |
        #!/bin/bash
        echo "[$(date)] 启动VMSS终止事件监听器" | logger -t termination-listener
        
        # 初始化日志函数
        log_info() {
          echo "[$(date)] $1" | logger -t termination-listener
        }
        
        log_debug() {
          echo "[$(date)] $1" | logger -t termination-listener-debug
        }
        
        while true; do
          # 查询 IMDS 终止事件
          EVENT=$(curl -H Metadata:true -s "http://169.254.169.254/metadata/scheduledevents?api-version=2020-07-01")
          
          # 先进行基本检查，确保EVENT不为空且格式正确
          if [[ -z "$EVENT" ]]; then
            log_debug "无法获取事件数据，将在5秒后重试"
            sleep 5
            continue
          fi
          
          # 检查是否有事件
          HAS_EVENTS=false
          if echo "$EVENT" | jq -e '.Events' > /dev/null 2>&1; then
            # 检查事件是否不为空数组
            if [[ $(echo "$EVENT" | jq -r '.Events | length') -gt 0 ]]; then
              # 检查是否有终止或抢占事件
              if echo "$EVENT" | jq -e '.Events[] | select(.EventType=="Terminate" or .EventType=="Preempt")' > /dev/null 2>&1; then
                HAS_EVENTS=true
                # 记录详细的事件信息
                EVENT_DETAILS=$(echo "$EVENT" | jq -c '.Events[] | select(.EventType=="Terminate" or .EventType=="Preempt")')
                log_info "检测到终止事件: $EVENT_DETAILS"
              else
                log_debug "有事件，但不是终止或抢占事件"
              fi
            else
              log_debug "事件列表为空"
            fi
            log_debug "事件数据格式不正确: $EVENT"
          fi
          
          if [[ "$HAS_EVENTS" == "true" ]]; then
            # 通过 curl 让容器变为 unhealthy
            log_info "通过 curl 让容器变为 unhealthy，负载均衡器将停止路由流量"
            curl -X GET http://127.0.0.1:80/ca23db1113754d319df6e679eb830a31
            log_info "已通知容器变为 unhealthy，等待最多10分钟处理剩余请求"
            # 记录到特殊日志，方便确认这是真实终止事件
            echo "[$(date)] 实例将被终止 - 事件详情: $EVENT_DETAILS" | logger -t termination-confirmed
            # 保持脚本运行，但停止检查
            sleep 600
            break
          else
            # 只输出简短日志，避免过多日志
            log_debug "未检测到终止事件，继续监听..."
          fi
          # 每5秒检查一次
          sleep 5
        done

  - path: /etc/systemd/system/termination-listener.service
    owner: root:root
    permissions: '0644'
    content: |
      [Unit]
      Description=Azure VMSS Termination Event Listener
      After=network.target
      
      [Service]
      Type=simple
      ExecStart=/usr/local/bin/termination-listener.sh
      Restart=always
      
      [Install]
      WantedBy=multi-user.target

runcmd:
  - |
    # export DEBIAN_FRONTEND=noninteractive
    # echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
    # echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
    # sysctl -w net.ipv4.ip_forward=1
    # iptables -t nat -A PREROUTING -p tcp --dport 5566 -j REDIRECT --to-port 22
    # netfilter-persistent save
    # curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
    systemctl daemon-reload
    systemctl enable podman-upload-server.service
    systemctl start podman-upload-server.service
    systemctl enable termination-listener.service
    systemctl start termination-listener.service
  