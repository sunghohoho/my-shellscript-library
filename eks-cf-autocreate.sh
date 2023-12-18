#!/bin/bash

#eks의 경우 ingress 리소스는 alb, svc 리소스의 경우 nlb가 생성됩니다
#네임스페이스와 리소스 네임을 입력하면 자동으로 clodufront + route53에 등록을 하는 쉘 스크립트 

#도메인 입력 ex) gguduck.com 인 경우 gguduck.com 입력
echo "Write your Domain Name : "
read dns
echo "ns is $1"
echo "svc or ingress resource! - $2"

# 입력한 리소스가 ingress인지 svc인지 확인 cheker가 1이면 svc, 0이면 ingress
runner=$(kubectl get svc -n $1 $2 -o jsonpath='{.spec.type}')

if [ $runner = "LoadBalancer" ]; then
  checker=1
else
  checker=0
fi

#svc 타입인 경우 nlb의 hostname과 port를 가져옴
if [ $checker -eq 1 ];  then
  
  echo "type is NetworkLoadBalancer"
  albarn=$(kubectl get svc -n $1 $2 -o jsonpath='{.status.loadBalancer.ingress[].hostname}')
  mainport=$(kubectl get svc -n $1 $2 -o jsonpath='{.spec.ports[].port}')
  prefix=$(kubectl get svc -n $1 $2 -o jsonpath='{.metadata.name}')
  suffix=$(kubectl get svc -n $1 $2 -o jsonpath='{.metadata.namespace}')
  record=$suffix-$prefix
  
  echo "elbarn is - $albarn"
  echo "port is - $mainport"
  echo "record is - $record"
  
else

#ingress 타입인 경우 alb의 hostname과 / 경로의 포트를 가져옴
  echo "type is ApplicationLoadBalancer"
  albarn=$(kubectl get ingress -n $1 $2 -o jsonpath='{.status.loadBalancer.ingress[].hostname}')
  mainport=$(kubectl get ingress -n $1 $2 -o jsonpath='{.spec.rules[].http.paths[?(@.path=="/")].backend.service.port.number}')
  prefix=$(kubectl get ingress -n $1 $2 -o jsonpath='{.metadata.name}')
  suffix=$(kubectl get ingress -n $1 $2 -o jsonpath='{.metadata.namespace}')
  record=$suffix-$prefix
  
  echo "elbarn is - $albarn"
  echo "port is - $mainport"
  echo "record is - $record"
  
fi

#acm 인증서 arn 가져오기, aws리소스내에 입력한 도메인에 대한 *.dns인 acm이 있는 경우 가능, cf의 경우 글로벌 서비스로 us-east-1에 acm을 가져옴
acmarn=$(aws acm list-certificates --region us-east-1 --query 'CertificateSummaryList[?DomainName==`*.'"${dns}"'`].CertificateArn[]' --output text)
echo "acmarn is - $acmarn"

#Cloudfront conf 작성
cat << EOF > conf.json
{
    "CallerReference": "$albarn",
    "Aliases": {
        "Quantity": 1,
        "Items" : [
            "${record}.${dns}"
        ]
    },
    "DefaultRootObject": "",
    "Origins": {
        "Quantity": 1,
        "Items": [
            {
                "Id": "$albarn",
                "DomainName": "$albarn",
                "OriginPath": "",
                "CustomHeaders": {
                    "Quantity": 0
                },
                    "CustomOriginConfig": {
                        "HTTPPort": ${mainport},
                        "HTTPSPort": 443,
                        "OriginProtocolPolicy": "http-only",
                        "OriginSslProtocols": {
                            "Quantity": 1,
                            "Items": [
                                "TLSv1.2"
                            ]
                        },
                        "OriginReadTimeout": 30,
                        "OriginKeepaliveTimeout": 5
                    },
                    "ConnectionAttempts": 3,
                    "ConnectionTimeout": 10,
                    "OriginShield": {
                        "Enabled": false
                    },
                    "OriginAccessControlId": ""
                }
            ]
        },
    "OriginGroups": {
        "Quantity": 0
    },
    "DefaultCacheBehavior": {
        "TargetOriginId": "$albarn",
        "ForwardedValues": {
            "QueryString": false,
            "Cookies": {
                "Forward": "none"
            },
            "Headers": {
                "Quantity": 0
            },
            "QueryStringCacheKeys": {
                "Quantity": 0
            }
        },
        "TrustedSigners": {
            "Enabled": false,
            "Quantity": 0
        },
        "ViewerProtocolPolicy": "allow-all",
        "MinTTL": 0,
        "AllowedMethods": {
            "Quantity": 2,
            "Items": [
                "HEAD",
                "GET"
            ],
            "CachedMethods": {
                "Quantity": 2,
                "Items": [
                    "HEAD",
                    "GET"
                ]
            }
        },
        "SmoothStreaming": false,
        "Compress": false,
        "LambdaFunctionAssociations": {
            "Quantity": 0
        },
        "FieldLevelEncryptionId": ""
    },
    "CacheBehaviors": {
        "Quantity": 0
    },
    "CustomErrorResponses": {
        "Quantity": 0
    },
    "Comment": "",
    "Logging": {
        "Enabled": false,
        "IncludeCookies": false,
        "Bucket": "",
        "Prefix": ""
    },
    "PriceClass": "PriceClass_All",
    "Enabled": true,
    "ViewerCertificate": {
        "CloudFrontDefaultCertificate": false,
        "ACMCertificateArn": "${acmarn}",
        "SSLSupportMethod": "sni-only",
        "MinimumProtocolVersion": "TLSv1.2_2021",
        "Certificate": "${acmarn}",
        "CertificateSource": "acm"
    },
    "Restrictions": {
        "GeoRestriction": {
            "RestrictionType": "none",
            "Quantity": 0
        }
    },
    "WebACLId": "",
    "HttpVersion": "http2",
    "IsIPV6Enabled": true
}
EOF

# Cloudfront 생성
cfarn=$(aws cloudfront create-distribution \
  --distribution-config file://conf.json --output text --query 'Distribution.DomainName') 

echo "cf domainname is - $cfarn"

#conf 파일 삭제
rm -f conf.json

#route53 레코드 추가하기
#1. hostedzone id 가져오기
hostedzoneid2=$(aws route53 list-hosted-zones  --output text --query 'HostedZones[?Config.PrivateZone==`false` && Name==`'"${dns}."'`].Id')    #변경필요
hostedzoneid=$(expr "$hostedzoneid2" : '.*/\([^/]*\)$')
echo "hostedzoneid is - $hostedzoneid"


#2 dns record 파일 생성
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

#3. 레코드 등록하기
aws route53 change-resource-record-sets --hosted-zone-id ${hostedzoneid} --change-batch file://recordfile.conf

echo "address is - https://${record}.${dns}"
