# 🏷️ **Bun Commerce**

_A Closed-Source Modular E-Commerce Platform_

---

**Author:** Mohammed Alhajeen  
**Project Type:** Commercial / Closed-Source Platform  
**Status:** Active Development  
**Architectural Origin:** Inspired by Suqnna Marketplace

---

## 🧭 Overview

**Bun Commerce** is a commercial-grade e-commerce platform designed for long-term scalability, domain extensibility, and real-world operational constraints.

- It is **not** a simple marketplace implementation.
- Bun Commerce focuses on building a **reusable commerce engine** capable of supporting multiple business models, product types, and market contexts.

The platform is architecturally inspired by the open research and experimentation conducted in the **Suqnna Marketplace** project, but is fully re-designed, hardened, and extended as a **private commercial system**.

---

## 🧠 Design Philosophy

Bun Commerce is built around one core principle:

> **E-commerce systems should evolve — not be rewritten.**

To support this, the platform emphasizes:

- **Strong domain boundaries**
- **Explicit business rules**
- **Minimal operational assumptions**
- **Controlled system growth**
- **Intellectual property protection**

---

## 🏗️ Core Platform Capabilities

| Capability                           | Description                                                                         |
| ------------------------------------ | ----------------------------------------------------------------------------------- |
| **Multi-Tenant Commerce Engine**     | Supports independent companies operating within a shared infrastructure.            |
| **Advanced Product Modeling**        | Flexible catalog with dynamic attributes, variants, and customization.              |
| **Order-Centric Architecture**       | Orders modeled as first-class domain entities with clear lifecycle states.          |
| **Deposit & Pre-Order Support**      | Native support for partial payments and handmade/pre-order workflows.               |
| **Escrow-Oriented Wallet Logic**     | Transaction flows designed for safety, reversibility, and auditability.             |
| **Modular Pricing Rules**            | Pricing logic isolated from products to support future strategies.                  |
| **Role-Separated Access Control**    | Clear separation of customer, company, and operational roles.                       |
| **Arabic-Ready Search Layer**        | Optimized PostgreSQL Full-Text Search for Arabic content.                           |
| **Scalable Modular Backend**         | Designed as a modular monolith with microservice-ready boundaries.                  |

---

## 🧩 Domain-Driven Module Structure

| Module         | Responsibility                                           |
| -------------- | -------------------------------------------------------- |
| **Architecture** | System boundaries and core abstractions                  |
| **Media**        | Media ownership, validation, and lifecycle               |
| **Company**      | Company isolation and storefront identity                |
| **Catalog**      | Products, attributes, and customization logic            |
| **Cart**         | Multi-company cart aggregation and validation            |
| **Order**        | Order lifecycle and state transitions                    |
| **Shipment**     | Delivery workflows and assignment                        |
| **Wallet**       | Escrow and transaction abstraction                       |
| **Security**     | Authentication and authorization boundaries              |
| **Data**         | PostgreSQL schema, indexing, and query optimization      |

---

## ⚙️ Technology Stack

- **Language:** Java 25
- **Framework:** Spring Boot 3.x
- **Database:** PostgreSQL 17
- **Authentication:** JWT + RBAC
- **Search:** PostgreSQL Full-Text Search (Arabic)
- **Containerization:** Docker & Docker Compose
- **Deployment:** Nginx-based container stack

---

## 🔒 Source Code & Access

This repository represents a **closed-source commercial platform**.

- ✅ Source code is **private**
- ✅ Business logic and domain rules are **protected**
- ✅ Public access is **intentionally limited**
- ⚠️ **This is NOT open-source software**

Architectural discussions, diagrams, and conceptual explanations may be shared independently.

---
## 🧬 Relationship to Suqnna Marketplace

**Bun Commerce** is an **independently developed, closed-source commercial platform**.

Some early architectural ideas and domain modeling experiments were informed by
lessons learned from **Suqnna Marketplace**, an academic prototype released
under the MIT License.

Bun Commerce is **not a continuation** of the Suqnna project and is **not affiliated**
with the original graduation team.

---

## 📚 Open-Source References and Acknowledgements

### 1) Suqnna Marketplace (MIT License)

**Suqnna Marketplace** was released under the **MIT License**:

```
MIT License

© 2025 Suqnna Graduation Team

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
```

---

### 2) Arabic Stopwords Collection by Gene Diaz (MIT License)

Bun Commerce includes components derived from an Arabic stopwords collection
originally authored by **Gene Diaz** and released under the **MIT License**.

```
The MIT License (MIT)

Copyright (c) 2016 Gene Diaz

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
```

---

## 🔍 Clear Separation

* **Suqnna Marketplace**
  Open-source academic prototype (MIT Licensed)
  Research, experimentation, and validation only

* **Arabic Stopwords Collection (Gene Diaz)**
  Open-source linguistic dataset (MIT Licensed)
  Attribution-only dependency

* **Bun Commerce**
  Closed-source proprietary product
  Independently engineered commercial platform

Bun Commerce does **not** redistribute the Suqnna source code or the original
Arabic stopwords dataset.

It only leverages:

* ✅ Architectural patterns validated during academic research
* ✅ Domain modeling experiments refined through prototyping
* ✅ Technical trade-offs documented during early design iterations
* ✅ Linguistic normalization logic derived from open datasets

> **Suqnna served as a research prototype.**
> **Open-source datasets informed early design.**
> **Bun Commerce delivers the commercial-grade system.**

---

## 🌱 Long-Term Vision

To evolve **Bun Commerce** into a **general-purpose commerce engine** capable of
powering multiple regional and vertical marketplaces without architectural rewrites.

---

## 🧠 Final Legal Note

Bun Commerce is built with **product responsibility**, **engineering discipline**,
and **long-term ownership** in mind.

It prioritizes **correctness**, **evolution**, and **sustainability** over feature count.

All third-party components are used in compliance with their respective licenses.
Full license texts are included above for transparency and legal completeness.
#   b u n _ c o m m e r c e - p u b l i c  
 