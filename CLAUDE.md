# CLAUDE.md

# HOFA Development Guide

## Project Overview

HOFA là nền tảng thương mại điện tử giao nhanh.

## Technology Stack

### Frontend

-   Flutter 3.x
-   Dart
-   Riverpod
-   GoRouter
-   Dio
-   flutter_secure_storage
-   flutter_map
-   latlong2
-   Firebase Cloud Messaging
-   Responsive Framework

Architecture: - Clean Architecture - Feature First - Repository
Pattern - Dependency Injection

### Backend

-   Node.js
-   Express.js
-   Deploy: Render
-   REST API
-   JWT + Refresh Token + RBAC

### Database

-   PostgreSQL (Supabase)

### Storage

-   Supabase Storage

### Maps & Navigation

Map Provider - OpenStreetMap (OSM)

Packages - flutter_map - latlong2

Routing - OSRM

Geocoding - Nominatim

Features - Driver Tracking - Customer Tracking - ETA - Route Planning -
Reverse Geocoding - Address Search

Do NOT use: - Google Maps SDK - Google Directions API - Google Distance
Matrix API - Google Geocoding API

### API Testing

-   Postman

### Source Control

-   Git
-   GitHub

## Deployment

Flutter Apps ↓ Firebase Hosting

Backend ↓ Render

Database ↓ Supabase PostgreSQL

Storage ↓ Supabase Storage

## Flutter Rules

-   Riverpod only
-   GoRouter
-   Clean Architecture
-   Feature First
-   Không viết Business Logic trong Widget.
-   Không gọi API trong UI.
-   Không truy cập Database trong Presentation.

## API Rules

``` json
{"success":true,"message":"Success","data":{}}
```

``` json
{"success":false,"message":"...","errorCode":"..."}
```

## Coding Rules

Luôn dùng: - Repository Pattern - DTO → Mapper → Entity - SOLID - DRY -
KISS

Không: - Hardcode URL - Hardcode màu - SQL trong UI

## Security

-   HTTPS
-   JWT
-   Refresh Token
-   RBAC
-   Flutter Secure Storage

## Development Workflow

Requirement → Database → API → Backend → Postman → Flutter Repository →
Riverpod → UI → Testing → Deploy

## AI Coding Rules

-   Tuân thủ SDD.
-   Không tự tạo Business Rules.
-   PostgreSQL là database chính.
-   Render deploy backend.
-   Supabase Storage lưu file.
-   OSM + OSRM + Nominatim cho toàn bộ chức năng bản đồ.
-   Code production-ready.
