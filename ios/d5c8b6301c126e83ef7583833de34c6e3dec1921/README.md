# Little Leonardo guided signing

Source `d5c8b6301c126e83ef7583833de34c6e3dec1921`. Thirteen native reader tests passed on the isolated iOS 26.5 simulator, which was shut down after testing. Image assets and signatures are synthetic. The iOS executable was unchanged from its build at a5f967ca27c5f0ebfbd3f4d96c15b87be91b3700. Only the macOS signing inspector and compilation ledger changed since the prior candidate. The wrapper verified that the iOS source and build inputs were unchanged and the executable digest matched before and after the exact-head run.
