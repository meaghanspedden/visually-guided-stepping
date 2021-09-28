import clr
import sys
import os
import logging

# Add a reference to the NMotive assembly.
clr.AddReference("NMotive")

# Import everything from NMotive.
from NMotive import *

def changeFileExtension(fileName, newExtension):
    """Changes the file extension of a file name to a specified one
	For example if the inputs are fileName="foo.txt" and newExtension="py"
	this function will return "foo.py"
	
	Args:
	   fileName (str): the file name int which the change is to be made.
	   newExtension (str): The new extension. The extension may or may
	       not include the '.'
	   
	Returns:
	   The file name with the old extension, if any, changed to the new.
	"""
	
    dotString = '' if '.' in newExtension else '.'
    nameWithoutExtenion = os.path.splitext(os.path.basename(fileName))[0]
    return '{0}{1}{2}'.format(nameWithoutExtenion, dotString, newExtension)

	
def takesInDirectory(dir):
    """Generator for generating NMotive Take objects for each file
    in a given directory with a .tak extension (a Motive take file).

    Args:
        dir (str): The directory containing the Motive take files.

    Returns:
        Take: An NMotive take object"""
	
    logger = logging.getLogger(__name__)
    files = [tf for tf in os.listdir(dir) if tf.endswith('.tak')]
    for f in files:
      takeFilePath = os.path.join(dir,f)
      logger.info('Loading take file %s', takeFilePath)
      t = None
      try:
        t = Take(takeFilePath)
      except NMotiveException as e:
          logger.error('Exception loading take %s: %s', takeFilePath, str(e))
          continue
      yield t
      # t.Finalize()
      #t.Dispose()

	  
def processAndExportTakes( dir, processors, export_creator):
    """Processes all the take files in a given directory and exports the
	the resulting takes using the given exporter. Takes that are NOT successfully
	processed are not exported.
	
	Args:
	    dir (str): the directory containing the take files.
		processors (TakeProcessor[]): an array of NMotive TakeProcessor objects.
		    Takes objects will be run each processor beginning with the first in
			the array.
		exporter (Exporter): an NMotive Exporter object used to export each take if
		    if it is successfully processed."""
			
    logger = logging.getLogger(__name__)
    files = [tf for tf in os.listdir(dir) if tf.endswith('.tak')]
    for t in takesInDirectory(dir):		  
       for p in processors:
          logger.info('Executing process %s on take %s', p.Name, t.Name)
          processResult = p.Process(t)
          if not processResult.Success:
             logger.error('Process {0} failed for take {1}: {2}.'.format( p.Name, t.Name, processResult.Message))
             continue
       exporter = export_creator()
       exportedFileName = changeFileExtension( t.FileName, exporter.Extension)
       exportedFilePath = os.path.join(dir, exportedFileName)
       logger.info('Begin exporting take %s to %s format, file %s', t.Name, exporter.Extension, exportedFilePath)
       
       exportResult = exporter.Export(t, exportedFilePath, True)
       exporter.Dispose()
       if (not exportResult.Success):
          logger.error('Error exporting take %s to %s format: %s', t.Name, exporter.Extension, exportResult.Message)
       else:
          logger.info('Take %s successfully exported to %s format, file %s', t.Name, exporter.Extension, exportedFilePath)
       t.Dispose()