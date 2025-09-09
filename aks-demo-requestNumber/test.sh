# 设置kubeconfig
$env:KUBECONFIG = "D:\6_demo\terraform-infra-set-up\kubeconfig-eastus2"

# 检查所有命名空间的资源
kubectl get all -n birdfy-vision-namespace

# 检查KEDA ScaledObject
kubectl get scaledobject -n birdfy-vision-namespace

#检查triggerauthentication
kubectl get triggerauthentication -n birdfy-vision-namespace

# 检查HPA (KEDA会创建HPA)
kubectl get hpa -n birdfy-vision-namespace

# 检查Ingress
# 检查Pod状态
kubectl get pods -n birdfy-vision-namespace

wrk -t4 -c200 -d20m http://demo.ingress.zzzdev666.com/v1/completions

kubectl describe pod 