/* TightEncodingReader.m created by helmut on 31-Oct-2000 */

/* Copyright (C) 1998-2000  Helmut Maierhofer <helmut.maierhofer@chello.at>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 *
 */

#import "TightEncodingReader.h"
#import "ZipLengthReader.h"
#import "PaletteFilter.h"
#import "FrameBufferUpdateReader.h"
#import "GradientFilter.h"
#import "CARD8Reader.h"
#import "ByteBlockReader.h"
#import "RFBConnection.h"
#import "Macros.h"

static void JpegInitSource(j_decompress_ptr cinfo)
{
}

static boolean JpegFillInputBuffer(j_decompress_ptr cinfo)
{
	return YES;
}

static void JpegSkipInputData(j_decompress_ptr cinfo, long num_bytes)
{
	if (num_bytes > 0 && num_bytes <= cinfo->src->bytes_in_buffer) {
		cinfo->src->next_input_byte += (size_t) num_bytes;
		cinfo->src->bytes_in_buffer -= (size_t) num_bytes;
	}
}

static void JpegTermSource(j_decompress_ptr cinfo)
{
}

static void JpegSetSrcManager(j_decompress_ptr cinfo, CARD8* compressedData, int compressedLen)
{
	cinfo->src->init_source = JpegInitSource;
	cinfo->src->fill_input_buffer = JpegFillInputBuffer;
	cinfo->src->skip_input_data = JpegSkipInputData;
	cinfo->src->resync_to_restart = jpeg_resync_to_restart;
	cinfo->src->term_source = JpegTermSource;
	cinfo->src->next_input_byte = compressedData;
	cinfo->src->bytes_in_buffer = compressedLen;
}

@implementation TightEncodingReader

- (id)initWithUpdater: (FrameBufferUpdateReader *)aUpdater connection: (RFBConnection *)aConnection
{
    if (self = [super initWithUpdater: aUpdater connection: aConnection]) {
		controlReader = [[CARD8Reader alloc] initTarget:self action:@selector(setControl:)];
		backPixReader = [[ByteBlockReader alloc] initTarget:self action:@selector(setBackground:)];
		filterIdReader = [[CARD8Reader alloc] initTarget:self action:@selector(setFilterId:)];
		unzippedDataReader = [[ByteBlockReader alloc] initTarget:self action:@selector(setUnzippedData:)];
		zippedDataReader = [[ByteBlockReader alloc] initTarget:self action:@selector(setZippedData:)];
		zipLengthReader = [[ZipLengthReader alloc] initTarget:self action:@selector(setZipLength:)];

        copyFilter = [[FilterReader alloc] initWithTarget:self andConnection:connection];
        paletteFilter = [[PaletteFilter alloc] initWithTarget:self andConnection:connection];
        gradientFilter = [[GradientFilter alloc] initWithTarget:self andConnection:connection];

		zBuffer = [[NSMutableData alloc] initWithLength:Z_BUFSIZE];
	}
    return self;
}

- (void)dealloc
{
    int streamID;

    for(streamID=0; streamID<NUM_ZSTREAMS; streamID++) {
		[self uninitializeStream: streamID];
    }
    [controlReader release];
    [backPixReader release];
    [filterIdReader release];
    [unzippedDataReader release];
    [zippedDataReader release];
    [zipLengthReader release];
    [copyFilter release];
    [paletteFilter release];
    [gradientFilter release];
    [zBuffer release];
    [super dealloc];
}

- (void)setFrameBuffer:(id)aBuffer
{
    [super setFrameBuffer:aBuffer];
    [backPixReader setBufferSize:[aBuffer tightBytesPerPixel]];
    [copyFilter setFrameBuffer:aBuffer];
    [paletteFilter setFrameBuffer:aBuffer];
    [gradientFilter setFrameBuffer:aBuffer];
}

- (void)readEncoding
{
    [frameBuffer setCurrentReaderIsTight: YES];
    [connection setReader:controlReader];
}

/* Have just read the initial control byte, which determines the subencoding */
- (void)setControl:(NSNumber*)cntlByte
{
    int streamId;
    
    cntl = [cntlByte unsignedCharValue];
    for(streamId=0; streamId<NUM_ZSTREAMS; streamId++) {
        if((cntl & 0x01)) {
			[self uninitializeStream: streamId];
        }
		cntl >>= 1;
    }
    if(cntl == rfbTightFill) {
        [connection setReader:backPixReader];
        return;
    }
	if(cntl == rfbTightJpeg) {
		[connection setReader:zipLengthReader];
		return;
	}
    if(cntl > rfbTightMaxSubencoding) {
        NSString    *err = ChickenVncFrameworkLocalizedString(@"TightBadSubencoding", nil);
		[connection terminateConnection:err];
        return;
    }
    if(cntl & rfbTightExplicitFilter) {
        [connection setReader:filterIdReader];
        return;
    }
    currentFilter = copyFilter;
    [currentFilter resetFilterForRect:frame];
}

- (void)setBackground:(NSData*)data
{
    [frameBuffer fillRect:frame tightPixel:(unsigned char*)[data bytes]];
    [frameBuffer setCurrentReaderIsTight:NO];
    [updater didRect:self];
}

- (void)setFilterId:(NSNumber*)aByte
{
    switch([aByte unsignedCharValue]) {
        case rfbTightFilterCopy:
            currentFilter = copyFilter;
            break;
        case rfbTightFilterPalette:
            currentFilter = paletteFilter;
            break;
        case rfbTightFilterGradient:
            currentFilter = gradientFilter;
            break;
        default:
            currentFilter = nil;
            NSString    *fmt = ChickenVncFrameworkLocalizedString(@"TightUnknownFilter", nil);
            NSString    *err = [NSString stringWithFormat:fmt, aByte];
            [connection terminateConnection:err];
            return;
    }
    [currentFilter resetFilterForRect:frame];
}

/* Whatever header the filter needs has now been processed */
- (void)filterInitDone
{
    int size;

    if((pixelBits = [currentFilter bitsPerPixel]) == 0) {
        NSString    *err = ChickenVncFrameworkLocalizedString(@"TightZeroPalette", nil);
        [connection terminateConnection:err];
        return;
    }
    rowSize = (frame.size.width * pixelBits + 7) / 8;
	NSParameterAssert( rowSize <= Z_BUFSIZE );
    size = rowSize * frame.size.height;
    if(size < TIGHT_MIN_TO_COMPRESS) {
        [unzippedDataReader setBufferSize:size];
        [connection setReader:unzippedDataReader];
        return;
    }
    [connection setReader:zipLengthReader];
}

- (void)setUnzippedData:(NSData*)data
{
    data = [currentFilter filter:data rows:frame.size.height];
    [frameBuffer putRect:frame fromTightData:(unsigned char*)[data bytes]];
    [frameBuffer setCurrentReaderIsTight:NO];
    [updater didRect:self];
}

- (void)setZipLength:(NSNumber*)zl
{
    int 	streamId, error;
    z_stream*	stream;

	if(cntl == rfbTightJpeg) {
		[zippedDataReader setBufferSize:[zl unsignedIntValue]];
		[connection setReader:zippedDataReader];
		return;
	}
    streamId = cntl & 0x03;
    stream = zStream + streamId;
    if(!zStreamActive[streamId]) {
		stream->next_in = Z_NULL;
		stream->avail_in = Z_NULL;
		stream->zalloc = Z_NULL;
        stream->zfree = Z_NULL;
        stream->opaque = Z_NULL;
        error = inflateInit(stream);
        if(error != Z_OK) {
            NSString *err;
            if(stream->msg != NULL) {
                NSString *fmt =ChickenVncFrameworkLocalizedString(@"TightInflateInitErrMsg",nil);
                err = [NSString stringWithFormat:fmt, stream->msg];
                [connection terminateConnection:[NSString stringWithFormat:fmt, stream->msg]];
            } else {
                err = ChickenVncFrameworkLocalizedString(@"TightInflateInitErr", nil);
            }
            [connection terminateConnection:err];
            return;
        }
        zStreamActive[streamId] = YES;
	}
    compressedLength = [zl unsignedIntValue];
    zBufPos = 0;
    rowsDone = 0;
    [zippedDataReader setBufferSize:MIN(compressedLength, Z_BUFSIZE)];
    [connection setReader:zippedDataReader];
}

- (void)setZippedData:(NSData*)data
{
    NSData* filtered;
    int numRows, error;
    z_stream* stream;
    NSRect r;
	

#ifdef ZDEBUG
	fwrite([data bytes], 1, [data length], debugFiles[cntl & 3]);
	fflush(debugFiles[cntl & 3]);
#endif

	if(cntl == rfbTightJpeg) {
		struct jpeg_decompress_struct cinfo;
		struct jpeg_error_mgr jerr;
		JSAMPROW rowPointer[1];
		unsigned char* buffer;
		NSRect r;

		cinfo.err = jpeg_std_error(&jerr);
		jpeg_create_decompress(&cinfo);
		cinfo.src = &jpegSrcManager;
		JpegSetSrcManager(&cinfo, (CARD8*)[data bytes], (int)[data length]);
		jpeg_read_header(&cinfo, TRUE);
		cinfo.out_color_space = JCS_RGB;
		jpeg_start_decompress(&cinfo);
		if(cinfo.output_width != frame.size.width || cinfo.output_height != frame.size.height || cinfo.output_components != 3) {
            NSString    *err = ChickenVncFrameworkLocalizedString(@"TightWrongJpeg", nil);
			[connection terminateConnection:err];
			jpeg_destroy_decompress(&cinfo);
			return;
		}
		buffer = malloc(3 * frame.size.width);
		rowPointer[0] = (JSAMPROW)buffer;
		r = frame;
		r.size.height = 1;
		while(cinfo.output_scanline < cinfo.output_height) {
			jpeg_read_scanlines(&cinfo, rowPointer, 1);
			[frameBuffer putRect:r fromRGBBytes:buffer];
			r.origin.y += 1;
		}
		free(buffer);
		jpeg_finish_decompress(&cinfo);
		jpeg_destroy_decompress(&cinfo);
        [frameBuffer setCurrentReaderIsTight:NO];
        [updater didRect:self];
		return;
	}
    stream = zStream + (cntl & 0x03);
    stream->next_in = (unsigned char*)[data bytes];
    stream->avail_in = (uint)[data length];
    do {
        stream->next_out = [zBuffer mutableBytes] + zBufPos;
        stream->avail_out = Z_BUFSIZE - zBufPos;
        error = inflate(stream, Z_SYNC_FLUSH);
		if (error == Z_BUF_ERROR)   /* Input exhausted -- no problem. */
			break;
        if((error != Z_OK) && (error != Z_STREAM_END)) {
            if(stream->msg != NULL) {
                [connection terminateConnection:[NSString stringWithFormat:@"Inflate error: %s.\n", stream->msg]];
            } else {
                NSString *err = ChickenVncFrameworkLocalizedString(@"TightInflateErr", nil);
                [connection terminateConnection:err];
            }
            return;
        }

        // write all the rows inflated in this cycle
        numRows = (Z_BUFSIZE - stream->avail_out) / rowSize;
        filtered = [currentFilter filter:zBuffer rows:numRows];
        r = frame;
        r.origin.y += rowsDone;
        r.size.height = numRows;
        [frameBuffer putRect:r fromTightData:(unsigned char*)[filtered bytes]];
        rowsDone += numRows;
        zBufPos = Z_BUFSIZE - stream->avail_out - numRows * rowSize;
        if(zBufPos > 0) {
            char* z = [zBuffer mutableBytes];
            memcpy(z, z + numRows * rowSize, zBufPos);
        }
    } while(stream->avail_out == 0);
    if((compressedLength -= [data length]) > 0) {
        [zippedDataReader setBufferSize:MIN(compressedLength, Z_BUFSIZE)];
        [connection setReader:zippedDataReader];
    } else {
        [frameBuffer setCurrentReaderIsTight:NO];
        [updater didRect:self];
    }
}

- (void)uninitializeStream: (int)streamID
{
	if(zStreamActive[streamID]) {
		if((inflateEnd(&zStream[streamID]) != Z_OK) && (zStream[streamID].msg != NULL)) {
			NSLog(@"inflateEnd: %s\n", zStream[streamID].msg);
		}
		zStreamActive[streamID] = NO;
	}
}

@end
