**1. kubectl jsonpath** <br/>
kubernetes 리소스의 경우 jsonpath를 지원해줘서 원하는 값을 가져올 수 있다.

ex) 생성된 ingress의 dns 주소를 가져오는 경우
~~~
kubectl get ingress -n default eks1-ingress -o jsonpath='{.status.loadBalancer.ingress[].hostname}'
~~~
<br/>
<br/>

**2. kubectl jsonpath 조건문** <br/>
kubernetes 리소스를 가져오는 경우 조건식등을 사용하여 원하는 값을 파싱할 수 있습니다.

ex) 생성된 ingress의 path가 / 인 경우의 포트 넘버를 가져오는 경우
~~~
kubectl get ingress -n $1 $2 -o jsonpath='{.spec.rules[].http.paths[?(@.path=="/")].backend.service.port.number}'
?(@.items=="조건식") 형태로 사용하여 조건식을 쓸 수 있습니다.
~~~
<br/>
<br/>

**3. aws cli를 통해 가져온 json 결과 값에서 원하는 정보를 파싱하는 경우** <br/>
get, list 등 cli를 통해 json값으로 받은 결과 값들에 대해서 원하는 정보를 파싱할 수 있음

ex) describe-load-balancers 를 통해 받은 결과 값에서 dns 이름만 파싱
~~~
aws elbv2 describe-load-balancers --load-balancer-arns $alb_arn --query "LoadBalancers[*].DNSName[]" --output text
--query "jsonpath" 형태로 사용하여 원하는 값들을 추출가능
~~~
<br/>
<br/>

**4. 쉘스크립트에서 파일을 생성해야하는 경우** <br/>
conffile등을 생성해야하는 경우

ex) route53 record 파일을 생성하는 경우
~~~
cat << EOF > recordfile.conf
{
  "Comment": "Creating Alias resource record sets in Route 53",
  "Changes": [
    {
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "${record}.${dns}",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "Z2FDTNDATAQYW2",
          "DNSName": "${cfarn}",
          "EvaluateTargetHealth": false
        }
      }
    }
  ]
}
EOF

aws route53 change-resource-record-sets --hosted-zone-id ${hostedzoneid} --change-batch file://recordfile.conf
~~~
와 같이 cat 명령어를 사용하여 파일 생성 후 적용이 가능하다.
<br/>
<br/>

**5. aws cli --query에서 환경변수 ($env)가 먹지 않은 경우** <br/>
aws --query 필터에서 환경변수를 가져오는 경우 잘안먹음

ex) 변수($dns)로 등록된 값과 동일한 주소를 가진 acm의 arn을 가져오는 경우
~~~
aws acm list-certificates --region us-east-1 --query 'CertificateSummaryList[?DomainName==`*.'"${dns}"'`].CertificateArn[]' --output text

[?Value==`'"$env"'`] 형태로 사용 가능
앞에 문자를 넣어야하는 경우도 가능
~~~
<br/>
<br/>

**6. 정규표현식** <br/>
값을 가져오는 경우 필요한 부분만 추출을 할 수 있습니다.

ex) aws list-hosted-zone 명령어를 사용하면 /hostedzone/Z07abcdeftghqQF6과 같이 출력이되며, 내가 필요한 값은 Z07abcdeftghqQF6이다. 이런 경우 뒤를 기준으로 첫 번째 / 가 나오는 경우 까지를 파싱했다. 
~~~
host=$(aws route53 list-hosted-zones  --output text --query 'HostedZones[?Config.PrivateZone==`false` && Name==`'"${dns}."'`].Id')
hostedid=$(expr "$host" : '.*/\([^/]*\)$')

list data is - /hostedzone/Z07abcdeftghqQF6
hostedzoneid is - Z07abcdeftghqQF6
~~~
