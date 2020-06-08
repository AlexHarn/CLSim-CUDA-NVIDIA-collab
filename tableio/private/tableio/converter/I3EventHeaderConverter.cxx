/**
 * copyright  (C) 2010
 * The Icecube Collaboration
 *
 * $Id: I3EventHeaderConverter.cxx 148889 2016-07-29 09:10:23Z jvansanten $
 *
 * @version $Revision: 148889 $
 * @date $LastChangedDate: 2016-07-29 03:10:23 -0600 (Fri, 29 Jul 2016) $
 * @author Eike Middell <eike.middell@desy.de> $LastChangedBy: jvansanten $
 */

#include "tableio/converter/I3EventHeaderConverter.h"

I3TableRowDescriptionPtr I3EventHeaderConverter::CreateDescription(const I3EventHeader& header) {
    
    I3TableRowDescriptionPtr desc(new I3TableRowDescription());
    desc->AddField<int64_t>("time_start_utc_daq", "1e-10 s", "start of event in daq time - tenths of nanoseconds since the start of the UTC year");
    desc->AddField<double> ("time_start_mjd",     "days",    "start of event in Modified Julian Days");
    desc->AddField<int64_t>("time_end_utc_daq",   "1e-10 s", "end of event in daq time - tenths of nanoseconds since the start of the UTC year");
    desc->AddField<double> ("time_end_mjd",       "days",    "end of event in Modified Julian Days");
    return desc;
}
    
size_t I3EventHeaderConverter::FillRows(const I3EventHeader& header,
                                        I3TableRowPtr rows) {
    I3Time start = header.GetStartTime();
    I3Time end = header.GetEndTime();

    rows->Set<int64_t>("time_start_utc_daq", start.GetUTCDaqTime());
    rows->Set<double >("time_start_mjd",  start.GetModJulianDayDouble());
    
    rows->Set<int64_t>("time_end_utc_daq", end.GetUTCDaqTime());
    rows->Set<double >("time_end_mjd",  end.GetModJulianDayDouble());

    return 1;
}
