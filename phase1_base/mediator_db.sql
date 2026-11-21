--
-- PostgreSQL database dump
--

\restrict d5g3T9U347CtcXiRGgeZcEyZBWOSMShVvSY3Jl7lOpgexBVJwObmoPsBjhEZxug

-- Dumped from database version 18.6 (Ubuntu 18.6-0ubuntu0.26.04.1)
-- Dumped by pg_dump version 18.6 (Ubuntu 18.6-0ubuntu0.26.04.1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: postgres_fdw; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS postgres_fdw WITH SCHEMA public;


--
-- Name: EXTENSION postgres_fdw; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION postgres_fdw IS 'foreign-data wrapper for remote PostgreSQL servers';


--
-- Name: distributor_server; Type: SERVER; Schema: -; Owner: postgres
--

CREATE SERVER distributor_server FOREIGN DATA WRAPPER postgres_fdw OPTIONS (
    dbname 'distributor_db',
    host '100.81.84.73',
    port '5432'
);


ALTER SERVER distributor_server OWNER TO postgres;

--
-- Name: USER MAPPING postgres SERVER distributor_server; Type: USER MAPPING; Schema: -; Owner: postgres
--

CREATE USER MAPPING FOR postgres SERVER distributor_server OPTIONS (
    password 'postgres',
    "user" 'postgres'
);


--
-- Name: manufacturer_server; Type: SERVER; Schema: -; Owner: postgres
--

CREATE SERVER manufacturer_server FOREIGN DATA WRAPPER postgres_fdw OPTIONS (
    dbname 'manufacturer_db',
    host '100.92.111.11',
    port '5432'
);


ALTER SERVER manufacturer_server OWNER TO postgres;

--
-- Name: USER MAPPING postgres SERVER manufacturer_server; Type: USER MAPPING; Schema: -; Owner: postgres
--

CREATE USER MAPPING FOR postgres SERVER manufacturer_server OPTIONS (
    password 'postgres123',
    "user" 'postgres'
);


--
-- Name: vendor_server; Type: SERVER; Schema: -; Owner: postgres
--

CREATE SERVER vendor_server FOREIGN DATA WRAPPER postgres_fdw OPTIONS (
    dbname 'vendor_db',
    host '100.122.110.0',
    port '5432'
);


ALTER SERVER vendor_server OWNER TO postgres;

--
-- Name: USER MAPPING postgres SERVER vendor_server; Type: USER MAPPING; Schema: -; Owner: postgres
--

CREATE USER MAPPING FOR postgres SERVER vendor_server OPTIONS (
    password 'postgres',
    "user" 'postgres'
);


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: approved_items; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.approved_items (
    approval_id integer NOT NULL,
    item_code character varying(50) NOT NULL,
    approved_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    approved_by character varying(100),
    approval_status character varying(20) DEFAULT 'APPROVED'::character varying,
    CONSTRAINT chk_approval_status CHECK (((approval_status)::text = 'APPROVED'::text))
);


ALTER TABLE public.approved_items OWNER TO postgres;

--
-- Name: approved_items_approval_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.approved_items_approval_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.approved_items_approval_id_seq OWNER TO postgres;

--
-- Name: approved_items_approval_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.approved_items_approval_id_seq OWNED BY public.approved_items.approval_id;


--
-- Name: distributors; Type: FOREIGN TABLE; Schema: public; Owner: postgres
--

CREATE FOREIGN TABLE public.distributors (
    distributor_id integer NOT NULL,
    distributor_name character varying(150) NOT NULL,
    license_number character varying(50) NOT NULL,
    address text,
    contact_number character varying(20)
)
SERVER distributor_server
OPTIONS (
    schema_name 'public',
    table_name 'distributors'
);
ALTER FOREIGN TABLE ONLY public.distributors ALTER COLUMN distributor_id OPTIONS (
    column_name 'distributor_id'
);
ALTER FOREIGN TABLE ONLY public.distributors ALTER COLUMN distributor_name OPTIONS (
    column_name 'distributor_name'
);
ALTER FOREIGN TABLE ONLY public.distributors ALTER COLUMN license_number OPTIONS (
    column_name 'license_number'
);
ALTER FOREIGN TABLE ONLY public.distributors ALTER COLUMN address OPTIONS (
    column_name 'address'
);
ALTER FOREIGN TABLE ONLY public.distributors ALTER COLUMN contact_number OPTIONS (
    column_name 'contact_number'
);


ALTER FOREIGN TABLE public.distributors OWNER TO postgres;

--
-- Name: inventory_items; Type: FOREIGN TABLE; Schema: public; Owner: postgres
--

CREATE FOREIGN TABLE public.inventory_items (
    inventory_id integer NOT NULL,
    distributor_id integer NOT NULL,
    product_code character varying(50) NOT NULL,
    received_date date NOT NULL
)
SERVER distributor_server
OPTIONS (
    schema_name 'public',
    table_name 'inventory_items'
);
ALTER FOREIGN TABLE ONLY public.inventory_items ALTER COLUMN inventory_id OPTIONS (
    column_name 'inventory_id'
);
ALTER FOREIGN TABLE ONLY public.inventory_items ALTER COLUMN distributor_id OPTIONS (
    column_name 'distributor_id'
);
ALTER FOREIGN TABLE ONLY public.inventory_items ALTER COLUMN product_code OPTIONS (
    column_name 'product_code'
);
ALTER FOREIGN TABLE ONLY public.inventory_items ALTER COLUMN received_date OPTIONS (
    column_name 'received_date'
);


ALTER FOREIGN TABLE public.inventory_items OWNER TO postgres;

--
-- Name: manufactured_items; Type: FOREIGN TABLE; Schema: public; Owner: postgres
--

CREATE FOREIGN TABLE public.manufactured_items (
    item_id integer NOT NULL,
    medicine_code character varying(30) NOT NULL,
    unique_item_code character varying(50) NOT NULL,
    manufacturing_date date NOT NULL,
    expiry_date date NOT NULL
)
SERVER manufacturer_server
OPTIONS (
    schema_name 'public',
    table_name 'manufactured_items'
);
ALTER FOREIGN TABLE ONLY public.manufactured_items ALTER COLUMN item_id OPTIONS (
    column_name 'item_id'
);
ALTER FOREIGN TABLE ONLY public.manufactured_items ALTER COLUMN medicine_code OPTIONS (
    column_name 'medicine_code'
);
ALTER FOREIGN TABLE ONLY public.manufactured_items ALTER COLUMN unique_item_code OPTIONS (
    column_name 'unique_item_code'
);
ALTER FOREIGN TABLE ONLY public.manufactured_items ALTER COLUMN manufacturing_date OPTIONS (
    column_name 'manufacturing_date'
);
ALTER FOREIGN TABLE ONLY public.manufactured_items ALTER COLUMN expiry_date OPTIONS (
    column_name 'expiry_date'
);


ALTER FOREIGN TABLE public.manufactured_items OWNER TO postgres;

--
-- Name: manufacturers; Type: FOREIGN TABLE; Schema: public; Owner: postgres
--

CREATE FOREIGN TABLE public.manufacturers (
    manufacturer_id integer NOT NULL,
    manufacturer_name character varying(150) NOT NULL,
    license_number character varying(50) NOT NULL,
    address text,
    contact_number character varying(20)
)
SERVER manufacturer_server
OPTIONS (
    schema_name 'public',
    table_name 'manufacturers'
);
ALTER FOREIGN TABLE ONLY public.manufacturers ALTER COLUMN manufacturer_id OPTIONS (
    column_name 'manufacturer_id'
);
ALTER FOREIGN TABLE ONLY public.manufacturers ALTER COLUMN manufacturer_name OPTIONS (
    column_name 'manufacturer_name'
);
ALTER FOREIGN TABLE ONLY public.manufacturers ALTER COLUMN license_number OPTIONS (
    column_name 'license_number'
);
ALTER FOREIGN TABLE ONLY public.manufacturers ALTER COLUMN address OPTIONS (
    column_name 'address'
);
ALTER FOREIGN TABLE ONLY public.manufacturers ALTER COLUMN contact_number OPTIONS (
    column_name 'contact_number'
);


ALTER FOREIGN TABLE public.manufacturers OWNER TO postgres;

--
-- Name: medicine_sales; Type: FOREIGN TABLE; Schema: public; Owner: postgres
--

CREATE FOREIGN TABLE public.medicine_sales (
    sale_id integer NOT NULL,
    item_identifier character varying(50) NOT NULL,
    vendor_id integer NOT NULL,
    sale_date date NOT NULL,
    customer_reference character varying(100)
)
SERVER vendor_server
OPTIONS (
    schema_name 'public',
    table_name 'medicine_sales'
);
ALTER FOREIGN TABLE ONLY public.medicine_sales ALTER COLUMN sale_id OPTIONS (
    column_name 'sale_id'
);
ALTER FOREIGN TABLE ONLY public.medicine_sales ALTER COLUMN item_identifier OPTIONS (
    column_name 'item_identifier'
);
ALTER FOREIGN TABLE ONLY public.medicine_sales ALTER COLUMN vendor_id OPTIONS (
    column_name 'vendor_id'
);
ALTER FOREIGN TABLE ONLY public.medicine_sales ALTER COLUMN sale_date OPTIONS (
    column_name 'sale_date'
);
ALTER FOREIGN TABLE ONLY public.medicine_sales ALTER COLUMN customer_reference OPTIONS (
    column_name 'customer_reference'
);


ALTER FOREIGN TABLE public.medicine_sales OWNER TO postgres;

--
-- Name: medicines; Type: FOREIGN TABLE; Schema: public; Owner: postgres
--

CREATE FOREIGN TABLE public.medicines (
    medicine_id integer NOT NULL,
    medicine_code character varying(30) NOT NULL,
    medicine_name character varying(150) NOT NULL,
    composition character varying(250),
    dosage_form character varying(50),
    manufacturer_id integer NOT NULL
)
SERVER manufacturer_server
OPTIONS (
    schema_name 'public',
    table_name 'medicines'
);
ALTER FOREIGN TABLE ONLY public.medicines ALTER COLUMN medicine_id OPTIONS (
    column_name 'medicine_id'
);
ALTER FOREIGN TABLE ONLY public.medicines ALTER COLUMN medicine_code OPTIONS (
    column_name 'medicine_code'
);
ALTER FOREIGN TABLE ONLY public.medicines ALTER COLUMN medicine_name OPTIONS (
    column_name 'medicine_name'
);
ALTER FOREIGN TABLE ONLY public.medicines ALTER COLUMN composition OPTIONS (
    column_name 'composition'
);
ALTER FOREIGN TABLE ONLY public.medicines ALTER COLUMN dosage_form OPTIONS (
    column_name 'dosage_form'
);
ALTER FOREIGN TABLE ONLY public.medicines ALTER COLUMN manufacturer_id OPTIONS (
    column_name 'manufacturer_id'
);


ALTER FOREIGN TABLE public.medicines OWNER TO postgres;

--
-- Name: supplied_items; Type: FOREIGN TABLE; Schema: public; Owner: postgres
--

CREATE FOREIGN TABLE public.supplied_items (
    supply_item_id integer NOT NULL,
    product_code character varying(50) NOT NULL,
    vendor_reference character varying(150) NOT NULL,
    supply_date date NOT NULL
)
SERVER distributor_server
OPTIONS (
    schema_name 'public',
    table_name 'supplied_items'
);
ALTER FOREIGN TABLE ONLY public.supplied_items ALTER COLUMN supply_item_id OPTIONS (
    column_name 'supply_item_id'
);
ALTER FOREIGN TABLE ONLY public.supplied_items ALTER COLUMN product_code OPTIONS (
    column_name 'product_code'
);
ALTER FOREIGN TABLE ONLY public.supplied_items ALTER COLUMN vendor_reference OPTIONS (
    column_name 'vendor_reference'
);
ALTER FOREIGN TABLE ONLY public.supplied_items ALTER COLUMN supply_date OPTIONS (
    column_name 'supply_date'
);


ALTER FOREIGN TABLE public.supplied_items OWNER TO postgres;

--
-- Name: vendor_inventory; Type: FOREIGN TABLE; Schema: public; Owner: postgres
--

CREATE FOREIGN TABLE public.vendor_inventory (
    inventory_id integer NOT NULL,
    vendor_id integer NOT NULL,
    distributor_id integer NOT NULL,
    item_identifier character varying(50) NOT NULL,
    received_date date NOT NULL
)
SERVER vendor_server
OPTIONS (
    schema_name 'public',
    table_name 'vendor_inventory'
);
ALTER FOREIGN TABLE ONLY public.vendor_inventory ALTER COLUMN inventory_id OPTIONS (
    column_name 'inventory_id'
);
ALTER FOREIGN TABLE ONLY public.vendor_inventory ALTER COLUMN vendor_id OPTIONS (
    column_name 'vendor_id'
);
ALTER FOREIGN TABLE ONLY public.vendor_inventory ALTER COLUMN distributor_id OPTIONS (
    column_name 'distributor_id'
);
ALTER FOREIGN TABLE ONLY public.vendor_inventory ALTER COLUMN item_identifier OPTIONS (
    column_name 'item_identifier'
);
ALTER FOREIGN TABLE ONLY public.vendor_inventory ALTER COLUMN received_date OPTIONS (
    column_name 'received_date'
);


ALTER FOREIGN TABLE public.vendor_inventory OWNER TO postgres;

--
-- Name: vendors; Type: FOREIGN TABLE; Schema: public; Owner: postgres
--

CREATE FOREIGN TABLE public.vendors (
    vendor_id integer NOT NULL,
    vendor_name character varying(150) NOT NULL,
    license_number character varying(50) NOT NULL,
    address text,
    contact_number character varying(20)
)
SERVER vendor_server
OPTIONS (
    schema_name 'public',
    table_name 'vendors'
);
ALTER FOREIGN TABLE ONLY public.vendors ALTER COLUMN vendor_id OPTIONS (
    column_name 'vendor_id'
);
ALTER FOREIGN TABLE ONLY public.vendors ALTER COLUMN vendor_name OPTIONS (
    column_name 'vendor_name'
);
ALTER FOREIGN TABLE ONLY public.vendors ALTER COLUMN license_number OPTIONS (
    column_name 'license_number'
);
ALTER FOREIGN TABLE ONLY public.vendors ALTER COLUMN address OPTIONS (
    column_name 'address'
);
ALTER FOREIGN TABLE ONLY public.vendors ALTER COLUMN contact_number OPTIONS (
    column_name 'contact_number'
);


ALTER FOREIGN TABLE public.vendors OWNER TO postgres;

--
-- Name: global_medicine_history; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.global_medicine_history AS
 SELECT mi.unique_item_code AS item_code,
    mi.medicine_code,
    m.medicine_name,
    m.composition,
    m.dosage_form,
    mf.manufacturer_id,
    mf.manufacturer_name,
    mi.manufacturing_date,
    mi.expiry_date,
        CASE
            WHEN (ai.item_code IS NOT NULL) THEN 'APPROVED'::text
            ELSE 'UNAPPROVED / NAKALI'::text
        END AS approval_status,
    ai.approved_at,
    ai.approved_by,
    vi.inventory_id AS vendor_inventory_id,
    vi.item_identifier AS vendor_item_code,
    vi.vendor_id,
    v.vendor_name,
    vi.distributor_id AS vendor_distributor_id,
    vi.received_date AS vendor_received_date,
    d.inventory_id AS distributor_inventory_id,
    d.product_code AS distributor_item_code,
    d.distributor_id,
    dist.distributor_name,
    d.received_date AS distributor_received_date,
    si.vendor_reference,
    si.supply_date,
    ms.sale_id,
    ms.sale_date,
    ms.customer_reference,
        CASE
            WHEN (mi.expiry_date < CURRENT_DATE) THEN 'EXPIRED'::text
            ELSE 'VALID'::text
        END AS expiry_status,
        CASE
            WHEN (ai.item_code IS NULL) THEN 'SUSPICIOUS'::text
            WHEN (mi.expiry_date < CURRENT_DATE) THEN 'SUSPICIOUS'::text
            WHEN (d.product_code IS NULL) THEN 'SUSPICIOUS'::text
            WHEN (d.distributor_id <> vi.distributor_id) THEN 'SUSPICIOUS'::text
            WHEN (vi.item_identifier IS NULL) THEN 'SUSPICIOUS'::text
            ELSE 'GENUINE'::text
        END AS risk_status,
        CASE
            WHEN (ai.item_code IS NULL) THEN 'UNAPPROVED / NAKALI'::text
            WHEN (mi.expiry_date < CURRENT_DATE) THEN 'EXPIRED ITEM'::text
            WHEN (d.product_code IS NULL) THEN 'DISTRIBUTOR RECORD NOT FOUND'::text
            WHEN (d.distributor_id <> vi.distributor_id) THEN 'DISTRIBUTOR ID MISMATCH'::text
            WHEN (vi.item_identifier IS NULL) THEN 'VENDOR RECORD NOT FOUND'::text
            ELSE NULL::text
        END AS suspicion_reason
   FROM (((((((((public.manufactured_items mi
     LEFT JOIN public.medicines m ON (((mi.medicine_code)::text = (m.medicine_code)::text)))
     LEFT JOIN public.manufacturers mf ON ((m.manufacturer_id = mf.manufacturer_id)))
     LEFT JOIN public.approved_items ai ON (((mi.unique_item_code)::text = (ai.item_code)::text)))
     LEFT JOIN public.inventory_items d ON (((mi.unique_item_code)::text = (d.product_code)::text)))
     LEFT JOIN public.distributors dist ON ((d.distributor_id = dist.distributor_id)))
     LEFT JOIN public.vendor_inventory vi ON (((mi.unique_item_code)::text = (vi.item_identifier)::text)))
     LEFT JOIN public.vendors v ON ((vi.vendor_id = v.vendor_id)))
     LEFT JOIN public.supplied_items si ON (((mi.unique_item_code)::text = (si.product_code)::text)))
     LEFT JOIN public.medicine_sales ms ON (((mi.unique_item_code)::text = (ms.item_identifier)::text)));


ALTER VIEW public.global_medicine_history OWNER TO postgres;

--
-- Name: mv_medicine_analysis; Type: MATERIALIZED VIEW; Schema: public; Owner: postgres
--

CREATE MATERIALIZED VIEW public.mv_medicine_analysis AS
 SELECT vi.item_identifier AS item_code,
    ms.sale_id,
    ms.sale_date,
    ms.customer_reference,
    vi.inventory_id AS vendor_inventory_id,
    vi.vendor_id,
    v.vendor_name,
    vi.distributor_id AS vendor_distributor_id,
    vi.received_date AS vendor_received_date,
    d.inventory_id AS distributor_inventory_id,
    d.product_code AS distributor_item_code,
    d.distributor_id,
    dist.distributor_name,
    d.received_date AS distributor_received_date,
    mi.medicine_code,
    m.medicine_name,
    m.composition,
    m.dosage_form,
    mf.manufacturer_id,
    mf.manufacturer_name,
    mi.manufacturing_date,
    mi.expiry_date,
        CASE
            WHEN (ai.item_code IS NOT NULL) THEN 'APPROVED'::text
            ELSE 'UNAPPROVED / NAKALI'::text
        END AS approval_status,
    ai.approved_at,
    ai.approved_by,
        CASE
            WHEN (mi.expiry_date < CURRENT_DATE) THEN 'EXPIRED'::text
            ELSE 'VALID'::text
        END AS expiry_status,
        CASE
            WHEN (vi.item_identifier IS NULL) THEN 'SUSPICIOUS'::text
            WHEN (ai.item_code IS NULL) THEN 'SUSPICIOUS'::text
            WHEN (mi.expiry_date < CURRENT_DATE) THEN 'SUSPICIOUS'::text
            WHEN (d.product_code IS NULL) THEN 'SUSPICIOUS'::text
            WHEN (d.distributor_id <> vi.distributor_id) THEN 'SUSPICIOUS'::text
            ELSE 'GENUINE'::text
        END AS analysis_status,
        CASE
            WHEN (vi.item_identifier IS NULL) THEN 'VENDOR RECORD NOT FOUND'::text
            WHEN (ai.item_code IS NULL) THEN 'UNAPPROVED / NAKALI'::text
            WHEN (mi.expiry_date < CURRENT_DATE) THEN 'EXPIRED ITEM'::text
            WHEN (d.product_code IS NULL) THEN 'DISTRIBUTOR RECORD NOT FOUND'::text
            WHEN (d.distributor_id <> vi.distributor_id) THEN 'DISTRIBUTOR ID MISMATCH'::text
            ELSE NULL::text
        END AS suspicion_reason
   FROM ((((((((public.vendor_inventory vi
     LEFT JOIN public.vendors v ON ((vi.vendor_id = v.vendor_id)))
     LEFT JOIN public.inventory_items d ON (((vi.item_identifier)::text = (d.product_code)::text)))
     LEFT JOIN public.distributors dist ON ((d.distributor_id = dist.distributor_id)))
     LEFT JOIN public.manufactured_items mi ON (((vi.item_identifier)::text = (mi.unique_item_code)::text)))
     LEFT JOIN public.medicines m ON (((mi.medicine_code)::text = (m.medicine_code)::text)))
     LEFT JOIN public.manufacturers mf ON ((m.manufacturer_id = mf.manufacturer_id)))
     LEFT JOIN public.approved_items ai ON (((vi.item_identifier)::text = (ai.item_code)::text)))
     LEFT JOIN public.medicine_sales ms ON (((vi.item_identifier)::text = (ms.item_identifier)::text)))
  WITH NO DATA;


ALTER MATERIALIZED VIEW public.mv_medicine_analysis OWNER TO postgres;

--
-- Name: reports; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.reports (
    report_id integer NOT NULL,
    item_identifier character varying(50) NOT NULL,
    manufacturer character varying(150),
    distributor character varying(150),
    vendor character varying(150),
    report_reason text NOT NULL,
    risk_status character varying(20) NOT NULL,
    evidence text NOT NULL,
    reported_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    status character varying(20) DEFAULT 'OPEN'::character varying,
    CONSTRAINT chk_report_risk_status CHECK (((risk_status)::text = 'SUSPICIOUS'::text)),
    CONSTRAINT chk_report_status CHECK (((status)::text = ANY ((ARRAY['OPEN'::character varying, 'UNDER_ANALYSIS'::character varying, 'CLOSED'::character varying])::text[])))
);


ALTER TABLE public.reports OWNER TO postgres;

--
-- Name: reports_report_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.reports_report_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.reports_report_id_seq OWNER TO postgres;

--
-- Name: reports_report_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.reports_report_id_seq OWNED BY public.reports.report_id;


--
-- Name: approved_items approval_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.approved_items ALTER COLUMN approval_id SET DEFAULT nextval('public.approved_items_approval_id_seq'::regclass);


--
-- Name: reports report_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.reports ALTER COLUMN report_id SET DEFAULT nextval('public.reports_report_id_seq'::regclass);


--
-- Data for Name: approved_items; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.approved_items (approval_id, item_code, approved_at, approved_by, approval_status) FROM stdin;
1	ITEM000205	2026-09-15 23:39:37.41786	Admin	APPROVED
2	ITEM000012	2026-09-15 23:39:37.41786	Admin	APPROVED
3	ITEM000254	2026-09-15 23:39:37.41786	Admin	APPROVED
4	ITEM000165	2026-09-15 23:39:37.41786	Admin	APPROVED
5	ITEM000258	2026-09-15 23:39:37.41786	Admin	APPROVED
6	ITEM000018	2026-09-15 23:39:37.41786	Admin	APPROVED
7	ITEM000152	2026-09-15 23:39:37.41786	Admin	APPROVED
8	ITEM000207	2026-09-15 23:39:37.41786	Admin	APPROVED
9	ITEM000265	2026-09-15 23:39:37.41786	Admin	APPROVED
10	ITEM000174	2026-09-15 23:39:37.41786	Admin	APPROVED
11	ITEM000163	2026-09-15 23:39:37.41786	Admin	APPROVED
12	ITEM000183	2026-09-15 23:39:37.41786	Admin	APPROVED
13	ITEM000056	2026-09-15 23:39:37.41786	Admin	APPROVED
14	ITEM000274	2026-09-15 23:39:37.41786	Admin	APPROVED
15	ITEM000050	2026-09-15 23:39:37.41786	Admin	APPROVED
16	ITEM000243	2026-09-15 23:39:37.41786	Admin	APPROVED
17	ITEM000150	2026-09-15 23:39:37.41786	Admin	APPROVED
18	ITEM000236	2026-09-15 23:39:37.41786	Admin	APPROVED
19	ITEM000186	2026-09-15 23:39:37.41786	Admin	APPROVED
20	ITEM000191	2026-09-15 23:39:37.41786	Admin	APPROVED
21	ITEM000098	2026-09-15 23:39:37.41786	Admin	APPROVED
22	ITEM000300	2026-09-15 23:39:37.41786	Admin	APPROVED
23	ITEM000156	2026-09-15 23:39:37.41786	Admin	APPROVED
24	ITEM000085	2026-09-15 23:39:37.41786	Admin	APPROVED
25	ITEM000147	2026-09-15 23:39:37.41786	Admin	APPROVED
26	ITEM000005	2026-09-15 23:39:37.41786	Admin	APPROVED
27	ITEM000092	2026-09-15 23:39:37.41786	Admin	APPROVED
28	ITEM000063	2026-09-15 23:39:37.41786	Admin	APPROVED
29	ITEM000083	2026-09-15 23:39:37.41786	Admin	APPROVED
30	ITEM000185	2026-09-15 23:39:37.41786	Admin	APPROVED
31	ITEM000021	2026-09-15 23:39:37.41786	Admin	APPROVED
32	ITEM000219	2026-09-15 23:39:37.41786	Admin	APPROVED
33	ITEM000268	2026-09-15 23:39:37.41786	Admin	APPROVED
34	ITEM000058	2026-09-15 23:39:37.41786	Admin	APPROVED
35	ITEM000023	2026-09-15 23:39:37.41786	Admin	APPROVED
36	ITEM000184	2026-09-15 23:39:37.41786	Admin	APPROVED
37	ITEM000032	2026-09-15 23:39:37.41786	Admin	APPROVED
38	ITEM000030	2026-09-15 23:39:37.41786	Admin	APPROVED
39	ITEM000113	2026-09-15 23:39:37.41786	Admin	APPROVED
40	ITEM000117	2026-09-15 23:39:37.41786	Admin	APPROVED
41	ITEM000068	2026-09-15 23:39:37.41786	Admin	APPROVED
42	ITEM000262	2026-09-15 23:39:37.41786	Admin	APPROVED
43	ITEM000239	2026-09-15 23:39:37.41786	Admin	APPROVED
44	ITEM000055	2026-09-15 23:39:37.41786	Admin	APPROVED
45	ITEM000007	2026-09-15 23:39:37.41786	Admin	APPROVED
46	ITEM000196	2026-09-15 23:39:37.41786	Admin	APPROVED
47	ITEM000139	2026-09-15 23:39:37.41786	Admin	APPROVED
48	ITEM000120	2026-09-15 23:39:37.41786	Admin	APPROVED
49	ITEM000269	2026-09-15 23:39:37.41786	Admin	APPROVED
50	ITEM000027	2026-09-15 23:39:37.41786	Admin	APPROVED
51	ITEM000167	2026-09-15 23:39:37.41786	Admin	APPROVED
52	ITEM000129	2026-09-15 23:39:37.41786	Admin	APPROVED
53	ITEM000278	2026-09-15 23:39:37.41786	Admin	APPROVED
54	ITEM000283	2026-09-15 23:39:37.41786	Admin	APPROVED
55	ITEM000214	2026-09-15 23:39:37.41786	Admin	APPROVED
56	ITEM000107	2026-09-15 23:39:37.41786	Admin	APPROVED
57	ITEM000281	2026-09-15 23:39:37.41786	Admin	APPROVED
58	ITEM000176	2026-09-15 23:39:37.41786	Admin	APPROVED
59	ITEM000084	2026-09-15 23:39:37.41786	Admin	APPROVED
60	ITEM000061	2026-09-15 23:39:37.41786	Admin	APPROVED
61	ITEM000017	2026-09-15 23:39:37.41786	Admin	APPROVED
62	ITEM000075	2026-09-15 23:39:37.41786	Admin	APPROVED
63	ITEM000133	2026-09-15 23:39:37.41786	Admin	APPROVED
64	ITEM000122	2026-09-15 23:39:37.41786	Admin	APPROVED
65	ITEM000118	2026-09-15 23:39:37.41786	Admin	APPROVED
66	ITEM000298	2026-09-15 23:39:37.41786	Admin	APPROVED
67	ITEM000238	2026-09-15 23:39:37.41786	Admin	APPROVED
68	ITEM000123	2026-09-15 23:39:37.41786	Admin	APPROVED
69	ITEM000137	2026-09-15 23:39:37.41786	Admin	APPROVED
70	ITEM000209	2026-09-15 23:39:37.41786	Admin	APPROVED
71	ITEM000142	2026-09-15 23:39:37.41786	Admin	APPROVED
72	ITEM000275	2026-09-15 23:39:37.41786	Admin	APPROVED
73	ITEM000192	2026-09-15 23:39:37.41786	Admin	APPROVED
74	ITEM000153	2026-09-15 23:39:37.41786	Admin	APPROVED
75	ITEM000296	2026-09-15 23:39:37.41786	Admin	APPROVED
76	ITEM000204	2026-09-15 23:39:37.41786	Admin	APPROVED
77	ITEM000211	2026-09-15 23:39:37.41786	Admin	APPROVED
78	ITEM000197	2026-09-15 23:39:37.41786	Admin	APPROVED
79	ITEM000043	2026-09-15 23:39:37.41786	Admin	APPROVED
80	ITEM000231	2026-09-15 23:39:37.41786	Admin	APPROVED
81	ITEM000060	2026-09-15 23:39:37.41786	Admin	APPROVED
82	ITEM000199	2026-09-15 23:39:37.41786	Admin	APPROVED
83	ITEM000029	2026-09-15 23:39:37.41786	Admin	APPROVED
84	ITEM000078	2026-09-15 23:39:37.41786	Admin	APPROVED
85	ITEM000172	2026-09-15 23:39:37.41786	Admin	APPROVED
86	ITEM000287	2026-09-15 23:39:37.41786	Admin	APPROVED
87	ITEM000089	2026-09-15 23:39:37.41786	Admin	APPROVED
88	ITEM000226	2026-09-15 23:39:37.41786	Admin	APPROVED
89	ITEM000190	2026-09-15 23:39:37.41786	Admin	APPROVED
90	ITEM000140	2026-09-15 23:39:37.41786	Admin	APPROVED
91	ITEM000182	2026-09-15 23:39:37.41786	Admin	APPROVED
92	ITEM000228	2026-09-15 23:39:37.41786	Admin	APPROVED
93	ITEM000097	2026-09-15 23:39:37.41786	Admin	APPROVED
94	ITEM000037	2026-09-15 23:39:37.41786	Admin	APPROVED
95	ITEM000046	2026-09-15 23:39:37.41786	Admin	APPROVED
96	ITEM000220	2026-09-15 23:39:37.41786	Admin	APPROVED
97	ITEM000201	2026-09-15 23:39:37.41786	Admin	APPROVED
98	ITEM000235	2026-09-15 23:39:37.41786	Admin	APPROVED
99	ITEM000100	2026-09-15 23:39:37.41786	Admin	APPROVED
100	ITEM000101	2026-09-15 23:39:37.41786	Admin	APPROVED
101	ITEM000057	2026-09-15 23:39:37.41786	Admin	APPROVED
102	ITEM000071	2026-09-15 23:39:37.41786	Admin	APPROVED
103	ITEM000099	2026-09-15 23:39:37.41786	Admin	APPROVED
104	ITEM000232	2026-09-15 23:39:37.41786	Admin	APPROVED
105	ITEM000244	2026-09-15 23:39:37.41786	Admin	APPROVED
106	ITEM000291	2026-09-15 23:39:37.41786	Admin	APPROVED
107	ITEM000206	2026-09-15 23:39:37.41786	Admin	APPROVED
108	ITEM000282	2026-09-15 23:39:37.41786	Admin	APPROVED
109	ITEM000279	2026-09-15 23:39:37.41786	Admin	APPROVED
110	ITEM000271	2026-09-15 23:39:37.41786	Admin	APPROVED
111	ITEM000045	2026-09-15 23:39:37.41786	Admin	APPROVED
112	ITEM000202	2026-09-15 23:39:37.41786	Admin	APPROVED
113	ITEM000248	2026-09-15 23:39:37.41786	Admin	APPROVED
114	ITEM000110	2026-09-15 23:39:37.41786	Admin	APPROVED
115	ITEM000076	2026-09-15 23:39:37.41786	Admin	APPROVED
116	ITEM000124	2026-09-15 23:39:37.41786	Admin	APPROVED
117	ITEM000221	2026-09-15 23:39:37.41786	Admin	APPROVED
118	ITEM000224	2026-09-15 23:39:37.41786	Admin	APPROVED
119	ITEM000146	2026-09-15 23:39:37.41786	Admin	APPROVED
120	ITEM000222	2026-09-15 23:39:37.41786	Admin	APPROVED
121	ITEM000031	2026-09-15 23:39:37.41786	Admin	APPROVED
122	ITEM000138	2026-09-15 23:39:37.41786	Admin	APPROVED
123	ITEM000188	2026-09-15 23:39:37.41786	Admin	APPROVED
124	ITEM000286	2026-09-15 23:39:37.41786	Admin	APPROVED
125	ITEM000299	2026-09-15 23:39:37.41786	Admin	APPROVED
126	ITEM000049	2026-09-15 23:39:37.41786	Admin	APPROVED
127	ITEM000285	2026-09-15 23:39:37.41786	Admin	APPROVED
128	ITEM000104	2026-09-15 23:39:37.41786	Admin	APPROVED
129	ITEM000181	2026-09-15 23:39:37.41786	Admin	APPROVED
130	ITEM000217	2026-09-15 23:39:37.41786	Admin	APPROVED
131	ITEM000033	2026-09-15 23:39:37.41786	Admin	APPROVED
132	ITEM000127	2026-09-15 23:39:37.41786	Admin	APPROVED
133	ITEM000067	2026-09-15 23:39:37.41786	Admin	APPROVED
134	ITEM000038	2026-09-15 23:39:37.41786	Admin	APPROVED
135	ITEM000255	2026-09-15 23:39:37.41786	Admin	APPROVED
136	ITEM000193	2026-09-15 23:39:37.41786	Admin	APPROVED
137	ITEM000128	2026-09-15 23:39:37.41786	Admin	APPROVED
138	ITEM000072	2026-09-15 23:39:37.41786	Admin	APPROVED
139	ITEM000195	2026-09-15 23:39:37.41786	Admin	APPROVED
140	ITEM000250	2026-09-15 23:39:37.41786	Admin	APPROVED
141	ITEM000175	2026-09-15 23:39:37.41786	Admin	APPROVED
142	ITEM000059	2026-09-15 23:39:37.41786	Admin	APPROVED
143	ITEM000162	2026-09-15 23:39:37.41786	Admin	APPROVED
144	ITEM000134	2026-09-15 23:39:37.41786	Admin	APPROVED
145	ITEM000041	2026-09-15 23:39:37.41786	Admin	APPROVED
146	ITEM000039	2026-09-15 23:39:37.41786	Admin	APPROVED
147	ITEM000136	2026-09-15 23:39:37.41786	Admin	APPROVED
148	ITEM000170	2026-09-15 23:39:37.41786	Admin	APPROVED
149	ITEM000131	2026-09-15 23:39:37.41786	Admin	APPROVED
150	ITEM000111	2026-09-15 23:39:37.41786	Admin	APPROVED
151	ITEM000187	2026-09-15 23:39:37.41786	Admin	APPROVED
152	ITEM000234	2026-09-15 23:39:37.41786	Admin	APPROVED
153	ITEM000034	2026-09-15 23:39:37.41786	Admin	APPROVED
154	ITEM000001	2026-09-15 23:39:37.41786	Admin	APPROVED
155	ITEM000112	2026-09-15 23:39:37.41786	Admin	APPROVED
156	ITEM000295	2026-09-15 23:39:37.41786	Admin	APPROVED
157	ITEM000148	2026-09-15 23:39:37.41786	Admin	APPROVED
158	ITEM000171	2026-09-15 23:39:37.41786	Admin	APPROVED
159	ITEM000227	2026-09-15 23:39:37.41786	Admin	APPROVED
160	ITEM000225	2026-09-15 23:39:37.41786	Admin	APPROVED
161	ITEM000121	2026-09-15 23:39:37.41786	Admin	APPROVED
162	ITEM000166	2026-09-15 23:39:37.41786	Admin	APPROVED
163	ITEM000253	2026-09-15 23:39:37.41786	Admin	APPROVED
164	ITEM000053	2026-09-15 23:39:37.41786	Admin	APPROVED
165	ITEM000132	2026-09-15 23:39:37.41786	Admin	APPROVED
166	ITEM000103	2026-09-15 23:39:37.41786	Admin	APPROVED
167	ITEM000161	2026-09-15 23:39:37.41786	Admin	APPROVED
168	ITEM000280	2026-09-15 23:39:37.41786	Admin	APPROVED
169	ITEM000066	2026-09-15 23:39:37.41786	Admin	APPROVED
170	ITEM000013	2026-09-15 23:39:37.41786	Admin	APPROVED
171	ITEM000240	2026-09-15 23:39:37.41786	Admin	APPROVED
172	ITEM000194	2026-09-15 23:39:37.41786	Admin	APPROVED
173	ITEM000130	2026-09-15 23:39:37.41786	Admin	APPROVED
174	ITEM000015	2026-09-15 23:39:37.41786	Admin	APPROVED
175	ITEM000213	2026-09-15 23:39:37.41786	Admin	APPROVED
176	ITEM000179	2026-09-15 23:39:37.41786	Admin	APPROVED
177	ITEM000178	2026-09-15 23:39:37.41786	Admin	APPROVED
178	ITEM000294	2026-09-15 23:39:37.41786	Admin	APPROVED
179	ITEM000095	2026-09-15 23:39:37.41786	Admin	APPROVED
180	ITEM000094	2026-09-15 23:39:37.41786	Admin	APPROVED
181	ITEM000109	2026-09-15 23:39:37.41786	Admin	APPROVED
182	ITEM000290	2026-09-15 23:39:37.41786	Admin	APPROVED
183	ITEM000010	2026-09-15 23:39:37.41786	Admin	APPROVED
184	ITEM000081	2026-09-15 23:39:37.41786	Admin	APPROVED
185	ITEM000230	2026-09-15 23:39:37.41786	Admin	APPROVED
186	ITEM000080	2026-09-15 23:39:37.41786	Admin	APPROVED
187	ITEM000158	2026-09-15 23:39:37.41786	Admin	APPROVED
188	ITEM000116	2026-09-15 23:39:37.41786	Admin	APPROVED
189	ITEM000048	2026-09-15 23:39:37.41786	Admin	APPROVED
190	ITEM000006	2026-09-15 23:39:37.41786	Admin	APPROVED
191	ITEM000164	2026-09-15 23:39:37.41786	Admin	APPROVED
192	ITEM000065	2026-09-15 23:39:37.41786	Admin	APPROVED
193	ITEM000288	2026-09-15 23:39:37.41786	Admin	APPROVED
194	ITEM000019	2026-09-15 23:39:37.41786	Admin	APPROVED
195	ITEM000062	2026-09-15 23:39:37.41786	Admin	APPROVED
196	ITEM000064	2026-09-15 23:39:37.41786	Admin	APPROVED
197	ITEM000252	2026-09-15 23:39:37.41786	Admin	APPROVED
198	ITEM000004	2026-09-15 23:39:37.41786	Admin	APPROVED
199	ITEM000180	2026-09-15 23:39:37.41786	Admin	APPROVED
200	ITEM000200	2026-09-15 23:39:37.41786	Admin	APPROVED
201	ITEM000177	2026-09-15 23:39:37.41786	Admin	APPROVED
202	ITEM000035	2026-09-15 23:39:37.41786	Admin	APPROVED
203	ITEM000145	2026-09-15 23:39:37.41786	Admin	APPROVED
204	ITEM000203	2026-09-15 23:39:37.41786	Admin	APPROVED
205	ITEM000008	2026-09-15 23:39:37.41786	Admin	APPROVED
206	ITEM000266	2026-09-15 23:39:37.41786	Admin	APPROVED
207	ITEM000070	2026-09-15 23:39:37.41786	Admin	APPROVED
208	ITEM000016	2026-09-15 23:39:37.41786	Admin	APPROVED
209	ITEM000087	2026-09-15 23:39:37.41786	Admin	APPROVED
210	ITEM000241	2026-09-15 23:39:37.41786	Admin	APPROVED
211	ITEM000047	2026-09-15 23:39:37.41786	Admin	APPROVED
212	ITEM000293	2026-09-15 23:39:37.41786	Admin	APPROVED
213	ITEM000090	2026-09-15 23:39:37.41786	Admin	APPROVED
214	ITEM000020	2026-09-15 23:39:37.41786	Admin	APPROVED
215	ITEM000247	2026-09-15 23:39:37.41786	Admin	APPROVED
216	ITEM000014	2026-09-15 23:39:37.41786	Admin	APPROVED
217	ITEM000105	2026-09-15 23:39:37.41786	Admin	APPROVED
218	ITEM000173	2026-09-15 23:39:37.41786	Admin	APPROVED
219	ITEM000297	2026-09-15 23:39:37.41786	Admin	APPROVED
220	ITEM000114	2026-09-15 23:39:37.41786	Admin	APPROVED
221	ITEM000249	2026-09-15 23:39:37.41786	Admin	APPROVED
222	ITEM000277	2026-09-15 23:39:37.41786	Admin	APPROVED
223	ITEM000144	2026-09-15 23:39:37.41786	Admin	APPROVED
224	ITEM000003	2026-09-15 23:39:37.41786	Admin	APPROVED
225	ITEM000284	2026-09-15 23:39:37.41786	Admin	APPROVED
226	ITEM000051	2026-09-15 23:39:37.41786	Admin	APPROVED
227	ITEM000024	2026-09-15 23:39:37.41786	Admin	APPROVED
228	ITEM000157	2026-09-15 23:39:37.41786	Admin	APPROVED
229	ITEM000160	2026-09-15 23:39:37.41786	Admin	APPROVED
230	ITEM000208	2026-09-15 23:39:37.41786	Admin	APPROVED
231	ITEM000267	2026-09-15 23:39:37.41786	Admin	APPROVED
232	ITEM000242	2026-09-15 23:39:37.41786	Admin	APPROVED
233	ITEM000246	2026-09-15 23:39:37.41786	Admin	APPROVED
234	ITEM000151	2026-09-15 23:39:37.41786	Admin	APPROVED
235	ITEM000263	2026-09-15 23:39:37.41786	Admin	APPROVED
236	ITEM000002	2026-09-15 23:39:37.41786	Admin	APPROVED
237	ITEM000040	2026-09-15 23:39:37.41786	Admin	APPROVED
238	ITEM000079	2026-09-15 23:39:37.41786	Admin	APPROVED
239	ITEM000245	2026-09-15 23:39:37.41786	Admin	APPROVED
240	ITEM000154	2026-09-15 23:39:37.41786	Admin	APPROVED
241	ITEM000088	2026-09-15 23:39:37.41786	Admin	APPROVED
242	ITEM000273	2026-09-15 23:39:37.41786	Admin	APPROVED
243	ITEM000218	2026-09-15 23:39:37.41786	Admin	APPROVED
244	ITEM000168	2026-09-15 23:39:37.41786	Admin	APPROVED
245	ITEM000009	2026-09-15 23:39:37.41786	Admin	APPROVED
246	ITEM000042	2026-09-15 23:39:37.41786	Admin	APPROVED
247	ITEM000251	2026-09-15 23:39:37.41786	Admin	APPROVED
248	ITEM000159	2026-09-15 23:39:37.41786	Admin	APPROVED
249	ITEM000272	2026-09-15 23:39:37.41786	Admin	APPROVED
250	ITEM000264	2026-09-15 23:39:37.41786	Admin	APPROVED
251	WXY	2026-09-16 17:25:32.094563	Admin	APPROVED
\.


--
-- Data for Name: reports; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.reports (report_id, item_identifier, manufacturer, distributor, vendor, report_reason, risk_status, evidence, reported_at, status) FROM stdin;
9	AAAG	ABC Pharma Ltd	\N	\N	UNAPPROVED / NAKALI	SUSPICIOUS	Item Code: AAAG\nMedicine: Paracetamol 500 mg\nManufacturer: ABC Pharma Ltd\nExpiry: 2028-09-16\nApproval: UNAPPROVED / NAKALI\nDistributor ID: None\nVendor Distributor ID: None	2026-09-16 04:45:38.732622	OPEN
10	WXY	ABC Pharma Ltd	\N	\N	UNAPPROVED / NAKALI	SUSPICIOUS	Item Code: WXY\nMedicine: Paracetamol 500 mg\nManufacturer: ABC Pharma Ltd\nExpiry: 2028-09-16\nApproval: UNAPPROVED / NAKALI\nDistributor ID: None\nVendor Distributor ID: None	2026-09-16 11:53:42.49211	OPEN
\.


--
-- Name: approved_items_approval_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.approved_items_approval_id_seq', 251, true);


--
-- Name: reports_report_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.reports_report_id_seq', 12, true);


--
-- Name: approved_items approved_items_item_code_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.approved_items
    ADD CONSTRAINT approved_items_item_code_key UNIQUE (item_code);


--
-- Name: approved_items approved_items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.approved_items
    ADD CONSTRAINT approved_items_pkey PRIMARY KEY (approval_id);


--
-- Name: reports reports_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.reports
    ADD CONSTRAINT reports_pkey PRIMARY KEY (report_id);


--
-- Name: reports unique_report_item; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.reports
    ADD CONSTRAINT unique_report_item UNIQUE (item_identifier);


--
-- Name: mv_medicine_analysis; Type: MATERIALIZED VIEW DATA; Schema: public; Owner: postgres
--

REFRESH MATERIALIZED VIEW public.mv_medicine_analysis;


--
-- PostgreSQL database dump complete
--

\unrestrict d5g3T9U347CtcXiRGgeZcEyZBWOSMShVvSY3Jl7lOpgexBVJwObmoPsBjhEZxug

