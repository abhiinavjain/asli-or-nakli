
# Asli-or-Nakli 💊

**Asli-or-Nakli** is a distributed medicine verification system that checks the authenticity and supply-chain history of an individual medicine using its **unique item code**.

## What We Built

We designed the system using **four independent PostgreSQL databases**:

* **Manufacturer DB** – stores manufacturers, medicines, and individually manufactured items along with manufacturing and expiry dates.
* **Distributor DB** – stores distributors, items received, and items supplied to vendors.
* **Vendor DB** – stores vendors and the individual medicine items available in their inventory.
* **Mediator DB** – integrates all three databases, performs verification, and stores suspicious-item reports.

The databases remain independent and communicate through **PostgreSQL Foreign Data Wrappers (FDW)**.

Since different databases use different names for the same item identifier, we perform schema mapping:

```text
Manufacturer        Distributor          Vendor
unique_item_code →  product_code    →   item_identifier
```

## Verification

When a user enters an item code, the Mediator checks its information across the distributed databases and determines whether the item is:

* **Genuine / Consistent**
* **Expired**
* **Suspicious**

The system can detect cases such as:

* Item missing from Distributor records
* Item supplied by Distributor but missing from Vendor inventory
* Distributor ID mismatch at Vendor
* Expired medicine
* Unapproved medicine

Suspicious cases are recorded in the Mediator's reporting system with supporting evidence.

## Technology Stack

* **PostgreSQL** – Distributed databases
* **PostgreSQL FDW** – Database communication and federation
* **SQL** – Integration and verification logic
* **Python** – User interface

## Architecture

```text
Manufacturer DB ──┐
                  │
Distributor DB ───┼──> Mediator DB ──> GUI
                  │
Vendor DB ────────┘
```

The project demonstrates how **heterogeneous distributed data can be integrated to produce a trustworthy, decision-centric medicine verification result.** 
