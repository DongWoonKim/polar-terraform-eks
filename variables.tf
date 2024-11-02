# 인프라 관련
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-2"
}

variable "vpc_name" {
  description = "Name of VPC"
  type        = string
  default     = "eks-vpc"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2c"]
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDR values"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDR values"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24"]
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}


# EKS 관련
variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "polar"
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.27"
}

variable "node_group_desired_size" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 2
}

variable "node_group_max_size" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 4
}

variable "node_group_min_size" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 1
}

variable "node_instance_types" {
  description = "List of instance types for the worker nodes"
  type        = list(string)
  default     = ["t3.medium"]
}

/*
CIDR(Classless Inter-Domain Routing) 주소 체계

1. VPC CIDR "10.0.0.0/16":
- /16은 첫 16비트가 네트워크 부분이라는 의미
- 즉, 10.0.까지가 고정
- 나머지 0.0 부분을 사용 가능 (약 65,536개의 IP 주소)
```
10.0.0.0 ~ 10.0.255.255 사용 가능
```

2. 서브넷 CIDR "/24":
- /24는 첫 24비트가 네트워크 부분
- 즉, 마지막 8비트만 호스트 부분 (256개의 IP)

3. Private Subnet:
```
10.0.1.0/24 => 10.0.1.0 ~ 10.0.1.255 (256개)
10.0.2.0/24 => 10.0.2.0 ~ 10.0.2.255 (256개)
```

4. Public Subnet:
```
10.0.101.0/24 => 10.0.101.0 ~ 10.0.101.255 (256개)
10.0.102.0/24 => 10.0.102.0 ~ 10.0.102.255 (256개)
```

일반적인 규칙:
- VPC는 보통 /16 사용 (큰 범위)
- 서브넷은 보통 /24 사용 (적당한 크기)
- Private은 앞쪽 번호 (1.x, 2.x)
- Public은 뒤쪽 번호 (101.x, 102.x)
  
이렇게 하는 이유:
1. 관리의 용이성
2. IP 대역 충돌 방지
3. 확장성 고려
4. Public/Private 구분 쉽게

****
CIDR의 숫자(/16, /24 등)는 네트워크 마스크의 비트 수를 내타낸다.

1. IP 주소는 32비트로 구성됨 (IPv4 기준)
```
10.0.0.0 = 00001010.00000000.00000000.00000000
```

2. /16의 의미:
```
10  .0   .0   .0
고정 고정 가변 가변
[   16비트   ][   16비트   ]
네트워크 부분 | 호스트 부분

사용가능한 IP 수: 2^16 = 65,536개
범위: 10.0.0.0 ~ 10.0.255.255
```

3. /24의 의미:
```
10  .0   .1   .0
고정 고정 고정 가변
[      24비트     ][8비트]
네트워크 부분     | 호스트

사용가능한 IP 수: 2^8 = 256개
범위: 예) 10.0.1.0 ~ 10.0.1.255
```

4. 다른 CIDR 예시:
```
/8  -> 2^24 = 16,777,216개 IP (매우 큼)
/16 -> 2^16 = 65,536개 IP (VPC에 적합)
/24 -> 2^8  = 256개 IP (서브넷에 적합)
/28 -> 2^4  = 16개 IP (작은 서브넷)
```

실제 계산 방법:
1. 32(전체 비트 수) - CIDR 숫자 = 가변 비트 수
2. 2^(가변 비트 수) = 사용 가능한 IP 개수

예시:
```
/16: 32-16 = 16비트 가변 -> 2^16 = 65,536개
/24: 32-24 = 8비트 가변 -> 2^8 = 256개
```

보통 AWS에서는:
- VPC는 /16 사용 (충분히 큰 범위)
- 서브넷은 /24 사용 (적당한 크기)

이렇게 하는 이유:
1. 관리 용이성
2. 미래 확장성
3. AWS 권장사항
4. 대부분의 워크로드에 적합한 크기
*/