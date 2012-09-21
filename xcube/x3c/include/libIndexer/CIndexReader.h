/**
 * @file CIndexFileReader.h
 *
 * @author bchaco
 *
 * CIndexReader class definition 
 */
#ifndef __CINDEXREADER_H__
#define __CINDEXREADER_H__

#include <string>
#include <vector>
#include <iosfwd>
#include "IdxFileFormat.h"

namespace x3c {
    namespace indexer {

        class CIndexReader
        {
        public:
            /**
             * Destructor
             */
            ~CIndexReader();

            /**
             * Closes the index file that was opened for either reading or writing.
             */
            void   close() const;

            /**
             * Returns the file offset for the closest index that is less than or
             * equal to <c>time</c>
             *
             * @param time the timestamp to search for
             * @param the offset from the start of the stream file
             * @return 0 on success
             */
            int getFilePosByTime(UINT64 time, UINT64 & pos) const;

            /**
             * Returns the number of records written
             */
            UINT32 numRecords() const;

            /**
             * Writes out the index file header
             *
             * @param stream to write out to
             */
            void dumpHeader(std::ostream &out);

            /**
             * Writes out the index file trailer
             *
             * @param stream to write out to
             */
            void dumpTrailer(std::ostream &out);

            /**
             * Writes out the index file
             *
             * @param stream to write out to
             */
            void dumpAll(std::ostream &out);

        private:

            /**
             * Constructor
             *
             * Construction supported only from CIndexer class
             */
            CIndexReader(CIndexer<CIndexReader> const& parent,
                         UINT32 reservedMem);

            /**
             * Construct a CIndexReader
             */
            bool create(std::string const& filename);

            /**
             * Assignment operator - not supported
             */
            CIndexReader& operator=(CIndexReader const&);

            /**
             * Copy assignment - not supported
             */
            CIndexReader(CIndexReader const&);

            /**
             * Initialize from an index file
             */
            bool constructFromFile();

            /** Full path to the index file on disk */
            std::string         mFilename;

            /** The index file header */
            IndexHeader         mHeader;

            /** Container of index records */
            std::vector<IndexRecord>  mIndexRecords;
            
            /** The index file trailer */
            IndexTrailer        mTrailer;

            /** The "parent" CIndexer instance */
            CIndexer<CIndexReader> const& mParent;

            /** File descriptor for an open Index file */
            mutable INT32       mFd;

            /** Allow construction and destruction only 
                from CIndexer<CIndexReader> */
            friend class CIndexer<CIndexReader>;

            friend std::ostream& operator<<(std::ostream &out, CIndexReader const& r);
        };

        /*
        ** Inline function implementation
        */

        inline UINT32 CIndexReader::numRecords() const
        {
            return (UINT32)mIndexRecords.size();
        }

    }   /* namespace indexer */
}  /* namespace x3c */


#endif /*  __CINDEXREADER_H__ */
