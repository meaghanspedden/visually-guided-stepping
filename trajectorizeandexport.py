import sys
import logging
import clr
import utils

# Add a reference to the NMotive assembly
clr.AddReference("NMotive")

# Import everything from sys and NMotive.
from System import *
from NMotive import *
dir=r'E:\Stepping\Subject_25\motive'


    # Take processing code here

traject=Trajectorizer() #construct trajectorizer instance
#exportobj=CSVExporter()
processors=[traject]
logging.basicConfig(level=logging.INFO)
utils.processAndExportTakes(dir,processors, CSVExporter)
 




