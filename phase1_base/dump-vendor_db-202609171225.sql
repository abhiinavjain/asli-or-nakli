--
-- PostgreSQL database dump
--

\restrict 2U5G7SN9NfGdqcOaE9AoCMWOoVaKrnrBMFnxUYtm6IJb9ProVcSEGY4hLQxtkUG

-- Dumped from database version 18.6 (Ubuntu 18.6-0ubuntu0.26.04.1)
-- Dumped by pg_dump version 18.6

-- Started on 2026-09-17 12:25:24

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

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 224 (class 1259 OID 16544)
-- Name: medicine_sales; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.medicine_sales (
    sale_id integer NOT NULL,
    item_identifier character varying(50) NOT NULL,
    vendor_id integer NOT NULL,
    sale_date date NOT NULL,
    customer_reference character varying(100)
);


ALTER TABLE public.medicine_sales OWNER TO postgres;

--
-- TOC entry 223 (class 1259 OID 16543)
-- Name: medicine_sales_sale_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.medicine_sales_sale_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.medicine_sales_sale_id_seq OWNER TO postgres;

--
-- TOC entry 3511 (class 0 OID 0)
-- Dependencies: 223
-- Name: medicine_sales_sale_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.medicine_sales_sale_id_seq OWNED BY public.medicine_sales.sale_id;


--
-- TOC entry 226 (class 1259 OID 16581)
-- Name: vendor_inventory; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.vendor_inventory (
    inventory_id integer NOT NULL,
    vendor_id integer NOT NULL,
    distributor_id integer NOT NULL,
    item_identifier character varying(50) NOT NULL,
    received_date date NOT NULL
);


ALTER TABLE public.vendor_inventory OWNER TO postgres;

--
-- TOC entry 225 (class 1259 OID 16580)
-- Name: vendor_inventory_inventory_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.vendor_inventory_inventory_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.vendor_inventory_inventory_id_seq OWNER TO postgres;

--
-- TOC entry 3512 (class 0 OID 0)
-- Dependencies: 225
-- Name: vendor_inventory_inventory_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.vendor_inventory_inventory_id_seq OWNED BY public.vendor_inventory.inventory_id;


--
-- TOC entry 222 (class 1259 OID 16511)
-- Name: vendors; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.vendors (
    vendor_id integer NOT NULL,
    vendor_name character varying(150) NOT NULL,
    license_number character varying(50) NOT NULL,
    address text,
    contact_number character varying(20)
);


ALTER TABLE public.vendors OWNER TO postgres;

--
-- TOC entry 221 (class 1259 OID 16510)
-- Name: vendors_vendor_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.vendors_vendor_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.vendors_vendor_id_seq OWNER TO postgres;

--
-- TOC entry 3513 (class 0 OID 0)
-- Dependencies: 221
-- Name: vendors_vendor_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.vendors_vendor_id_seq OWNED BY public.vendors.vendor_id;


--
-- TOC entry 3337 (class 2604 OID 16547)
-- Name: medicine_sales sale_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.medicine_sales ALTER COLUMN sale_id SET DEFAULT nextval('public.medicine_sales_sale_id_seq'::regclass);


--
-- TOC entry 3338 (class 2604 OID 16584)
-- Name: vendor_inventory inventory_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vendor_inventory ALTER COLUMN inventory_id SET DEFAULT nextval('public.vendor_inventory_inventory_id_seq'::regclass);


--
-- TOC entry 3336 (class 2604 OID 16514)
-- Name: vendors vendor_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vendors ALTER COLUMN vendor_id SET DEFAULT nextval('public.vendors_vendor_id_seq'::regclass);


--
-- TOC entry 3503 (class 0 OID 16544)
-- Dependencies: 224
-- Data for Name: medicine_sales; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.medicine_sales (sale_id, item_identifier, vendor_id, sale_date, customer_reference) FROM stdin;
1	MED001	1	2026-09-01	CUST001
2	MED002	2	2026-09-02	CUST002
3	MED003	3	2026-09-03	CUST003
4	MED004	4	2026-09-04	CUST004
5	MED005	5	2026-09-05	CUST005
6	MED006	6	2026-09-06	CUST006
7	MED007	7	2026-09-07	CUST007
8	MED008	8	2026-09-08	CUST008
9	MED009	9	2026-09-09	CUST009
10	WXY	10	2026-09-10	CUST010
\.


--
-- TOC entry 3505 (class 0 OID 16581)
-- Dependencies: 226
-- Data for Name: vendor_inventory; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.vendor_inventory (inventory_id, vendor_id, distributor_id, item_identifier, received_date) FROM stdin;
1	1	1	ITEM000003	2026-08-25
2	2	1	ITEM000050	2026-08-25
3	3	2	ITEM000088	2026-08-26
4	4	2	ITEM000095	2026-08-26
5	5	2	ITEM000097	2026-08-26
6	6	2	ITEM000099	2026-08-26
7	7	2	ITEM000102	2026-08-26
8	8	3	ITEM000135	2026-08-27
9	9	3	ITEM000144	2026-08-27
10	10	3	ITEM000146	2026-08-27
11	1	3	ITEM000170	2026-08-27
12	2	4	ITEM000186	2026-08-28
13	3	4	ITEM000191	2026-08-28
14	4	4	ITEM000204	2026-08-28
15	5	4	ITEM000207	2026-08-28
16	6	5	ITEM000263	2026-08-29
17	7	5	ITEM000281	2026-08-29
18	8	5	ITEM000284	2026-08-29
19	9	5	ITEM000287	2026-08-29
20	10	5	ITEM000297	2026-08-29
21	1	1	ITEM000021	2026-08-20
22	2	1	ITEM000022	2026-08-20
23	3	1	ITEM000023	2026-08-21
24	4	1	ITEM000024	2026-08-21
25	5	1	ITEM000025	2026-08-21
26	6	1	ITEM000026	2026-08-22
27	7	1	ITEM000027	2026-08-22
28	8	1	ITEM000028	2026-08-22
29	9	1	ITEM000029	2026-08-23
30	10	1	ITEM000030	2026-08-23
31	1	2	ITEM000031	2026-08-20
32	2	2	ITEM000032	2026-08-20
33	3	2	ITEM000033	2026-08-21
34	4	2	ITEM000034	2026-08-21
35	5	2	ITEM000035	2026-08-22
36	6	2	ITEM000036	2026-08-22
37	7	2	ITEM000037	2026-08-23
38	8	2	ITEM000038	2026-08-23
39	9	2	ITEM000039	2026-08-24
40	10	2	ITEM000040	2026-08-24
41	1	5	ITEM000061	2026-09-02
42	2	5	ITEM000062	2026-09-02
43	3	5	ITEM000063	2026-09-03
44	4	5	ITEM000064	2026-09-03
45	5	5	ITEM000065	2026-09-04
46	6	5	ITEM000066	2026-09-04
47	7	5	ITEM000067	2026-09-05
48	8	5	ITEM000068	2026-09-05
49	9	5	ITEM000069	2026-09-06
50	10	5	ITEM000070	2026-09-06
51	1	1	ITEM000001	2026-08-25
52	2	1	ITEM000002	2026-08-25
53	3	1	ITEM000004	2026-08-25
54	4	1	ITEM000005	2026-08-25
55	5	1	ITEM000006	2026-08-26
56	6	1	ITEM000007	2026-08-26
57	7	1	ITEM000008	2026-08-26
58	8	1	ITEM000009	2026-08-27
59	9	1	ITEM000010	2026-08-27
60	1	2	ITEM000052	2026-08-27
61	2	2	ITEM000053	2026-08-27
62	3	2	ITEM000054	2026-08-28
63	4	2	ITEM000055	2026-08-28
64	5	2	ITEM000056	2026-08-28
65	6	2	ITEM000057	2026-08-29
66	7	2	ITEM000058	2026-08-29
67	8	2	ITEM000059	2026-08-29
68	9	2	ITEM000060	2026-08-30
69	1	3	ITEM000071	2026-08-30
70	2	3	ITEM000072	2026-08-30
71	3	3	ITEM000073	2026-08-31
72	4	3	ITEM000074	2026-08-31
73	5	3	ITEM000075	2026-09-01
74	6	3	ITEM000076	2026-09-01
75	7	3	ITEM000077	2026-09-02
76	8	3	ITEM000078	2026-09-02
77	9	3	ITEM000079	2026-09-03
78	10	3	ITEM000080	2026-09-03
79	1	2	ITEM000106	2026-09-16
80	1	2	ITEM000108	2026-09-16
81	1	2	ITEM000115	2026-09-16
82	1	2	ITEM000119	2026-09-16
83	1	3	ITEM000125	2026-09-16
84	1	3	ITEM000126	2026-09-16
85	1	3	WXY	2026-09-16
\.


--
-- TOC entry 3501 (class 0 OID 16511)
-- Dependencies: 222
-- Data for Name: vendors; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.vendors (vendor_id, vendor_name, license_number, address, contact_number) FROM stdin;
1	CityCare Medical Store	DL-VEN-001	Karol Bagh, New Delhi	9820000001
2	Apollo Health Point	DL-VEN-002	Lajpat Nagar, New Delhi	9820000002
3	Wellness Pharmacy	DL-VEN-003	Dwarka, New Delhi	9820000003
4	LifeCare Medical Store	DL-VEN-004	Rohini, New Delhi	9820000004
5	GreenCross Pharmacy	DL-VEN-005	Saket, New Delhi	9820000005
6	MediTrust Pharmacy	DL-VEN-006	Janakpuri, New Delhi	9820000006
7	HealthFirst Medicals	DL-VEN-007	Pitampura, New Delhi	9820000007
8	CarePlus Pharmacy	DL-VEN-008	Mayur Vihar, New Delhi	9820000008
9	PrimeCare Medical Store	DL-VEN-009	Rajouri Garden, New Delhi	9820000009
10	SafeMeds Pharmacy	DL-VEN-010	Vasant Kunj, New Delhi	9820000010
\.


--
-- TOC entry 3514 (class 0 OID 0)
-- Dependencies: 223
-- Name: medicine_sales_sale_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.medicine_sales_sale_id_seq', 10, true);


--
-- TOC entry 3515 (class 0 OID 0)
-- Dependencies: 225
-- Name: vendor_inventory_inventory_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.vendor_inventory_inventory_id_seq', 86, true);


--
-- TOC entry 3516 (class 0 OID 0)
-- Dependencies: 221
-- Name: vendors_vendor_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.vendors_vendor_id_seq', 10, true);


--
-- TOC entry 3344 (class 2606 OID 16553)
-- Name: medicine_sales medicine_sales_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.medicine_sales
    ADD CONSTRAINT medicine_sales_pkey PRIMARY KEY (sale_id);


--
-- TOC entry 3346 (class 2606 OID 16555)
-- Name: medicine_sales unique_item_sale; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.medicine_sales
    ADD CONSTRAINT unique_item_sale UNIQUE (item_identifier);


--
-- TOC entry 3348 (class 2606 OID 16593)
-- Name: vendor_inventory vendor_inventory_item_identifier_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vendor_inventory
    ADD CONSTRAINT vendor_inventory_item_identifier_key UNIQUE (item_identifier);


--
-- TOC entry 3350 (class 2606 OID 16591)
-- Name: vendor_inventory vendor_inventory_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vendor_inventory
    ADD CONSTRAINT vendor_inventory_pkey PRIMARY KEY (inventory_id);


--
-- TOC entry 3340 (class 2606 OID 16523)
-- Name: vendors vendors_license_number_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vendors
    ADD CONSTRAINT vendors_license_number_key UNIQUE (license_number);


--
-- TOC entry 3342 (class 2606 OID 16521)
-- Name: vendors vendors_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vendors
    ADD CONSTRAINT vendors_pkey PRIMARY KEY (vendor_id);


--
-- TOC entry 3351 (class 2606 OID 16561)
-- Name: medicine_sales fk_sales_vendor; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.medicine_sales
    ADD CONSTRAINT fk_sales_vendor FOREIGN KEY (vendor_id) REFERENCES public.vendors(vendor_id) ON DELETE CASCADE;


--
-- TOC entry 3352 (class 2606 OID 16594)
-- Name: vendor_inventory fk_vendor_inventory_vendor; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vendor_inventory
    ADD CONSTRAINT fk_vendor_inventory_vendor FOREIGN KEY (vendor_id) REFERENCES public.vendors(vendor_id) ON DELETE CASCADE;


-- Completed on 2026-09-17 12:25:24

--
-- PostgreSQL database dump complete
--

\unrestrict 2U5G7SN9NfGdqcOaE9AoCMWOoVaKrnrBMFnxUYtm6IJb9ProVcSEGY4hLQxtkUG

