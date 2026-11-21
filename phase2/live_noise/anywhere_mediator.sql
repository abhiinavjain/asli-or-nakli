-- =====================================================================
-- Asli-or-Nakli · rehearsal: noise in OTHER columns · RUN ON: mediator_db
-- =====================================================================
-- approval recorded under a noisy code     expect: UPDATE approved_items ITEM00O275 to ITEM000275
-- (the GUI now also offers a fix script for mediator_db)
UPDATE public.approved_items SET item_code = 'ITEM00O275' WHERE item_code = 'ITEM000275';
