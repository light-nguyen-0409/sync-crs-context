# SPEC: GAP-747 Disable Docker Build Cache in AWS CodeBuild (buildspec.yml)

> **Task Key**: `GAP-747`
> **Trạng thái**: `DONE`
> **Ngày tạo**: 2026-10-21
> **Author**: Antigravity Pair Programmer
> **Scope**: CI/CD Pipeline / AWS CodeBuild Configuration (`buildspec.yml`)
> **Cross-links**:
> - Plan gốc: [.specs/GAP-747/001-upgrade-docker-runtime-to-php-8-2.md](file:///Users/nexusfrontiertech/projects/gap-web-backend/.specs/GAP-747/001-upgrade-docker-runtime-to-php-8-2.md)
> - Review findings: [.specs/GAP-747/002-fix-code-review-findings.md](file:///Users/nexusfrontiertech/projects/gap-web-backend/.specs/GAP-747/002-fix-code-review-findings.md)

---

## 1. Tổng quan

Khi phát hành bản vá bảo mật khẩn cấp (như PHP Core CVE-2026-109618 / CVE-2026-109619), cơ chế cache Docker layer (`--cache-from`) trong file `buildspec.yml` của AWS CodeBuild sẽ khiến lệnh `RUN apt-get update && apt-get install ...` bị bỏ qua (cache hit) nếu trước đó đã có image PHP 8.2 được build và lưu trên ECR. Kết quả là container xuất xưởng vẫn chứa binary PHP cũ chưa được vá.

Mục tiêu của spec này là:
1. Loại bỏ cờ `--cache-from $REPOSITORY_URI:latest` trong lệnh `docker build`.
2. Bổ sung cờ `--no-cache` để ép Docker build mới toàn bộ các layers, đảm bảo luôn tải gói PHP mới nhất từ PPA `ondrej/php`.
3. Loại bỏ lệnh `docker pull $REPOSITORY_URI:latest || true` ở phase `pre_build` để tiết kiệm thời gian build (không cần kéo image cũ về làm cache).

---

## 2. Database Design

`N/A — Không thay đổi Database.`

---

## 3. API Contract & API Docs Pre-Deployment Gate

`N/A — no API contract/API docs change.`
Thay đổi cấu hình CI/CD không làm ảnh hưởng đến API contract hay API documentation.

---

## 4. Chi tiết thay đổi kỹ thuật

### 4.1. File `buildspec.yml`

#### Hiện trạng:
```yaml
version: 0.2

phases:
  pre_build:
    commands:
      - echo Logging in to Amazon ECR...
      - aws --version
      - aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com
      - echo ${DOCKER_TOKEN} | docker login -u nexusgapdocker --password-stdin
      - REPOSITORY_URI=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${IMAGE_REPO_NAME}
      - COMMIT_HASH=$(echo $CODEBUILD_RESOLVED_SOURCE_VERSION | cut -c 1-7)
      - IMAGE_TAG=${COMMIT_HASH:=latest}
      - docker pull $REPOSITORY_URI:latest || true
  build:
    commands:
      - echo Build started on `date`
      - echo Building the Docker image...
      - docker build -t $REPOSITORY_URI:latest --cache-from $REPOSITORY_URI:latest --build-arg WWWGROUP=${WWWGROUP} --build-arg WWWUSER=${WWWUSER} -f ./docker/8.2/Dockerfile.production .
      - docker tag $REPOSITORY_URI:latest $REPOSITORY_URI:$IMAGE_TAG
  post_build:
    commands:
      - echo Build completed on `date`
      - echo Pushing the Docker images...
      - docker push $REPOSITORY_URI:latest
      - docker push $REPOSITORY_URI:$IMAGE_TAG
      - echo Writing image definitions file...
      - printf '[{"name":"backend","imageUri":"%s"}]' $REPOSITORY_URI:$IMAGE_TAG > imagedefinitions.json
artifacts:
  files: imagedefinitions.json
```

#### Đề xuất thay đổi:
1. **Phase `pre_build`**:
   - Xóa dòng `docker pull $REPOSITORY_URI:latest || true` (dòng 13) vì không dùng cache từ image cũ nữa.
2. **Phase `build`**:
   - Thay thế cờ `--cache-from $REPOSITORY_URI:latest` bằng cờ `--no-cache`.

```yaml
version: 0.2

phases:
  pre_build:
    commands:
      - echo Logging in to Amazon ECR...
      - aws --version
      - aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com
      - echo ${DOCKER_TOKEN} | docker login -u nexusgapdocker --password-stdin
      - REPOSITORY_URI=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${IMAGE_REPO_NAME}
      - COMMIT_HASH=$(echo $CODEBUILD_RESOLVED_SOURCE_VERSION | cut -c 1-7)
      - IMAGE_TAG=${COMMIT_HASH:=latest}
  build:
    commands:
      - echo Build started on `date`
      - echo Building the Docker image without cache...
      - docker build --no-cache -t $REPOSITORY_URI:latest --build-arg WWWGROUP=${WWWGROUP} --build-arg WWWUSER=${WWWUSER} -f ./docker/8.2/Dockerfile.production .
      - docker tag $REPOSITORY_URI:latest $REPOSITORY_URI:$IMAGE_TAG
  post_build:
    commands:
      - echo Build completed on `date`
      - echo Pushing the Docker images...
      - docker push $REPOSITORY_URI:latest
      - docker push $REPOSITORY_URI:$IMAGE_TAG
      - echo Writing image definitions file...
      - printf '[{"name":"backend","imageUri":"%s"}]' $REPOSITORY_URI:$IMAGE_TAG > imagedefinitions.json
artifacts:
  files: imagedefinitions.json
```

---

## 5. Files cần sửa đổi

| File | Thay đổi |
|------|----------|
| `buildspec.yml` | Bỏ `docker pull` ở `pre_build`, bỏ `--cache-from` và thêm `--no-cache` trong lệnh `docker build`. |

---

## 6. Kế hoạch Verification

1. **Kiểm tra cú pháp YAML**: Sử dụng linter/parser YAML để đảm bảo file `buildspec.yml` hợp lệ, không bị lỗi thụt dòng.
2. **Kiểm tra git diff**: Đảm bảo diff tối thiểu, chỉ chỉnh sửa đúng 2 vị trí liên quan đến cache (`pre_build` và `build`).
3. **Audit an toàn CI/CD**: Xác nhận biến môi trường và luồng tag/push image không bị xáo trộn.
