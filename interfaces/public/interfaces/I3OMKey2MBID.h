/**
 * copyright  (C) 2004
 * the icecube collaboration
 * $Id: I3OMKey2MBID.h 169292 2012-11-04 16:34:42Z nwhitehorn $
 *
 * @file I3OMKey2MBID.h
 * @version $Revision: 169292 $
 * @date $Date: 2012-11-04 09:34:42 -0700 (Sun, 04 Nov 2012) $
 */

#ifndef INTERFACES_I3OMKEY2MBID_H_INCLUDED
#define INTERFACES_I3OMKEY2MBID_H_INCLUDED

#include <icetray/I3DefaultName.h>
#include <icetray/I3Logging.h>
#include <icetray/I3PointerTypedefs.h>
#include <icetray/OMKey.h>

/**
 * @brief This is an icetray service which provides conversions
 * between OMKey and DOM mainboard id.
 */
class I3OMKey2MBID
{
 public:
  /**
   * Default constructor.
   */
  I3OMKey2MBID();
  /**
   * Destructor.
   */
  virtual ~I3OMKey2MBID();
  /**
   * Checks whether an OMKey exists for the given mbid.
   */
  virtual bool OMKeyExists(long long int mbid) const = 0;
  /**
   * @brief Gets the OMKey for the given mbid.
   */
  virtual OMKey GetOMKey(long long int mbid) const = 0;
  /**
   * Checks whether a mbid exists for the given OMKey.
   */
  virtual bool MBIDExists(OMKey key) const = 0;
  /**
   * @brief Gets the mbid for the given OMKey.
   */
  virtual long long int GetMBID(OMKey key) const = 0;

 private:
  // private copy constructors and assignment
  I3OMKey2MBID(const I3OMKey2MBID& rhs); 
  I3OMKey2MBID& operator=(const I3OMKey2MBID& rhs); 

  // logging
  SET_LOGGER("I3OMKey2MBID");
};

/**
 * pointer type to insulate users from memory management
 */
I3_POINTER_TYPEDEFS(I3OMKey2MBID);

/**
 * define a default name to address service in a context
 */
I3_DEFAULT_NAME(I3OMKey2MBID);

#endif /*I3OMKEY2MBID_H_INCLUDED*/
