.. Ara documentation master file, created by
   sphinx-quickstart on Tue Oct 25 15:56:10 2022.
   You can adapt this file completely to your liking, but it should at least
   contain the root `toctree` directive.

Welcome to Ara's documentation!
===============================

.. toctree::
   :maxdepth: 1
   :caption: Introduction:

   introduction

.. toctree::
   :maxdepth: 1
   :caption: SoC:

   modules/ara_soc.md
   modules/ara_system.md

.. toctree::
   :maxdepth: 1
   :caption: Ara:

   modules/ara.md
   modules/ara_dispatcher.md
   modules/segment_sequencer.md
   modules/ara_sequencer.md

.. toctree::
   :maxdepth: 1
   :caption: SLDU

   modules/sldu/sldu.md

.. toctree::
   :maxdepth: 1
   :caption: MASKU

   modules/masku/masku.md

.. toctree::
   :maxdepth: 1
   :caption: VLSU

   modules/vlsu/vlsu.md
   modules/vlsu/addrgen.md
   modules/vlsu/vldu.md
   modules/vlsu/vstu.md

.. toctree::
   :maxdepth: 1
   :caption: Lane

   modules/lane/lane.md
   modules/lane/lane_sequencer.md
   modules/lane/vrf.md
   modules/lane/operand_requester.md
   modules/lane/operand_queues_stage.md
   modules/lane/operand_queue.md
   modules/lane/vector_fus_stage.md
   modules/lane/valu.md
   modules/lane/simd_alu.md
   modules/lane/fixed_p_rounding.md
   modules/lane/vmfpu.md
   modules/lane/simd_mul.md
   modules/lane/simd_div.md
