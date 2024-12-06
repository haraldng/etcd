// Code generated by protoc-gen-gogo. DO NOT EDIT.
// source: recover_wal.proto

package proto

import (
	context "context"
	fmt "fmt"
	proto "github.com/gogo/protobuf/proto"
	grpc "google.golang.org/grpc"
	codes "google.golang.org/grpc/codes"
	status "google.golang.org/grpc/status"
	io "io"
	math "math"
	math_bits "math/bits"
)

// Reference imports to suppress errors if they are not otherwise used.
var _ = proto.Marshal
var _ = fmt.Errorf
var _ = math.Inf

// This is a compile-time assertion to ensure that this generated file
// is compatible with the proto package it is being compiled against.
// A compilation error at this line likely means your copy of the
// proto package needs to be updated.
const _ = proto.GoGoProtoPackageIsVersion3 // please upgrade the proto package

type MissingEntriesRequest struct {
	Indexes []uint64 `protobuf:"varint,1,rep,packed,name=indexes,proto3" json:"indexes,omitempty"`
}

func (m *MissingEntriesRequest) Reset()         { *m = MissingEntriesRequest{} }
func (m *MissingEntriesRequest) String() string { return proto.CompactTextString(m) }
func (*MissingEntriesRequest) ProtoMessage()    {}
func (*MissingEntriesRequest) Descriptor() ([]byte, []int) {
	return fileDescriptor_7bc6e55455feb1ed, []int{0}
}
func (m *MissingEntriesRequest) XXX_Unmarshal(b []byte) error {
	return m.Unmarshal(b)
}
func (m *MissingEntriesRequest) XXX_Marshal(b []byte, deterministic bool) ([]byte, error) {
	if deterministic {
		return xxx_messageInfo_MissingEntriesRequest.Marshal(b, m, deterministic)
	} else {
		b = b[:cap(b)]
		n, err := m.MarshalToSizedBuffer(b)
		if err != nil {
			return nil, err
		}
		return b[:n], nil
	}
}
func (m *MissingEntriesRequest) XXX_Merge(src proto.Message) {
	xxx_messageInfo_MissingEntriesRequest.Merge(m, src)
}
func (m *MissingEntriesRequest) XXX_Size() int {
	return m.Size()
}
func (m *MissingEntriesRequest) XXX_DiscardUnknown() {
	xxx_messageInfo_MissingEntriesRequest.DiscardUnknown(m)
}

var xxx_messageInfo_MissingEntriesRequest proto.InternalMessageInfo

func (m *MissingEntriesRequest) GetIndexes() []uint64 {
	if m != nil {
		return m.Indexes
	}
	return nil
}

type MissingEntriesResponse struct {
	Entries []*Entry `protobuf:"bytes,1,rep,name=entries,proto3" json:"entries,omitempty"`
}

func (m *MissingEntriesResponse) Reset()         { *m = MissingEntriesResponse{} }
func (m *MissingEntriesResponse) String() string { return proto.CompactTextString(m) }
func (*MissingEntriesResponse) ProtoMessage()    {}
func (*MissingEntriesResponse) Descriptor() ([]byte, []int) {
	return fileDescriptor_7bc6e55455feb1ed, []int{1}
}
func (m *MissingEntriesResponse) XXX_Unmarshal(b []byte) error {
	return m.Unmarshal(b)
}
func (m *MissingEntriesResponse) XXX_Marshal(b []byte, deterministic bool) ([]byte, error) {
	if deterministic {
		return xxx_messageInfo_MissingEntriesResponse.Marshal(b, m, deterministic)
	} else {
		b = b[:cap(b)]
		n, err := m.MarshalToSizedBuffer(b)
		if err != nil {
			return nil, err
		}
		return b[:n], nil
	}
}
func (m *MissingEntriesResponse) XXX_Merge(src proto.Message) {
	xxx_messageInfo_MissingEntriesResponse.Merge(m, src)
}
func (m *MissingEntriesResponse) XXX_Size() int {
	return m.Size()
}
func (m *MissingEntriesResponse) XXX_DiscardUnknown() {
	xxx_messageInfo_MissingEntriesResponse.DiscardUnknown(m)
}

var xxx_messageInfo_MissingEntriesResponse proto.InternalMessageInfo

func (m *MissingEntriesResponse) GetEntries() []*Entry {
	if m != nil {
		return m.Entries
	}
	return nil
}

type Entry struct {
	Index uint64 `protobuf:"varint,1,opt,name=index,proto3" json:"index,omitempty"`
	Term  uint64 `protobuf:"varint,2,opt,name=term,proto3" json:"term,omitempty"`
	Data  []byte `protobuf:"bytes,3,opt,name=data,proto3" json:"data,omitempty"`
}

func (m *Entry) Reset()         { *m = Entry{} }
func (m *Entry) String() string { return proto.CompactTextString(m) }
func (*Entry) ProtoMessage()    {}
func (*Entry) Descriptor() ([]byte, []int) {
	return fileDescriptor_7bc6e55455feb1ed, []int{2}
}
func (m *Entry) XXX_Unmarshal(b []byte) error {
	return m.Unmarshal(b)
}
func (m *Entry) XXX_Marshal(b []byte, deterministic bool) ([]byte, error) {
	if deterministic {
		return xxx_messageInfo_Entry.Marshal(b, m, deterministic)
	} else {
		b = b[:cap(b)]
		n, err := m.MarshalToSizedBuffer(b)
		if err != nil {
			return nil, err
		}
		return b[:n], nil
	}
}
func (m *Entry) XXX_Merge(src proto.Message) {
	xxx_messageInfo_Entry.Merge(m, src)
}
func (m *Entry) XXX_Size() int {
	return m.Size()
}
func (m *Entry) XXX_DiscardUnknown() {
	xxx_messageInfo_Entry.DiscardUnknown(m)
}

var xxx_messageInfo_Entry proto.InternalMessageInfo

func (m *Entry) GetIndex() uint64 {
	if m != nil {
		return m.Index
	}
	return 0
}

func (m *Entry) GetTerm() uint64 {
	if m != nil {
		return m.Term
	}
	return 0
}

func (m *Entry) GetData() []byte {
	if m != nil {
		return m.Data
	}
	return nil
}

func init() {
	proto.RegisterType((*MissingEntriesRequest)(nil), "proto.MissingEntriesRequest")
	proto.RegisterType((*MissingEntriesResponse)(nil), "proto.MissingEntriesResponse")
	proto.RegisterType((*Entry)(nil), "proto.Entry")
}

func init() { proto.RegisterFile("recover_wal.proto", fileDescriptor_7bc6e55455feb1ed) }

var fileDescriptor_7bc6e55455feb1ed = []byte{
	// 242 bytes of a gzipped FileDescriptorProto
	0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0xff, 0xe2, 0x12, 0x2c, 0x4a, 0x4d, 0xce,
	0x2f, 0x4b, 0x2d, 0x8a, 0x2f, 0x4f, 0xcc, 0xd1, 0x2b, 0x28, 0xca, 0x2f, 0xc9, 0x17, 0x62, 0x05,
	0x53, 0x4a, 0x86, 0x5c, 0xa2, 0xbe, 0x99, 0xc5, 0xc5, 0x99, 0x79, 0xe9, 0xae, 0x79, 0x25, 0x45,
	0x99, 0xa9, 0xc5, 0x41, 0xa9, 0x85, 0xa5, 0xa9, 0xc5, 0x25, 0x42, 0x12, 0x5c, 0xec, 0x99, 0x79,
	0x29, 0xa9, 0x15, 0xa9, 0xc5, 0x12, 0x8c, 0x0a, 0xcc, 0x1a, 0x2c, 0x41, 0x30, 0xae, 0x92, 0x03,
	0x97, 0x18, 0xba, 0x96, 0xe2, 0x82, 0xfc, 0xbc, 0xe2, 0x54, 0x21, 0x35, 0x2e, 0xf6, 0x54, 0x88,
	0x10, 0x58, 0x0f, 0xb7, 0x11, 0x0f, 0xc4, 0x32, 0x3d, 0x90, 0xc2, 0xca, 0x20, 0x98, 0xa4, 0x92,
	0x2b, 0x17, 0x2b, 0x58, 0x44, 0x48, 0x84, 0x8b, 0x15, 0x6c, 0xaa, 0x04, 0xa3, 0x02, 0xa3, 0x06,
	0x4b, 0x10, 0x84, 0x23, 0x24, 0xc4, 0xc5, 0x52, 0x92, 0x5a, 0x94, 0x2b, 0xc1, 0x04, 0x16, 0x04,
	0xb3, 0x41, 0x62, 0x29, 0x89, 0x25, 0x89, 0x12, 0xcc, 0x0a, 0x8c, 0x1a, 0x3c, 0x41, 0x60, 0xb6,
	0x51, 0x1c, 0x17, 0x57, 0xb8, 0xa3, 0x4f, 0x70, 0x6a, 0x51, 0x59, 0x66, 0x72, 0xaa, 0x50, 0x00,
	0x97, 0xa0, 0x7b, 0x6a, 0x09, 0xaa, 0xcb, 0x84, 0x64, 0xa0, 0x0e, 0xc0, 0xea, 0x47, 0x29, 0x59,
	0x1c, 0xb2, 0x10, 0xef, 0x38, 0x49, 0x9c, 0x78, 0x24, 0xc7, 0x78, 0xe1, 0x91, 0x1c, 0xe3, 0x83,
	0x47, 0x72, 0x8c, 0x13, 0x1e, 0xcb, 0x31, 0x5c, 0x78, 0x2c, 0xc7, 0x70, 0xe3, 0xb1, 0x1c, 0x43,
	0x12, 0x1b, 0x58, 0x9f, 0x31, 0x20, 0x00, 0x00, 0xff, 0xff, 0xe6, 0x6f, 0xe9, 0xbd, 0x58, 0x01,
	0x00, 0x00,
}

// Reference imports to suppress errors if they are not otherwise used.
var _ context.Context
var _ grpc.ClientConn

// This is a compile-time assertion to ensure that this generated file
// is compatible with the grpc package it is being compiled against.
const _ = grpc.SupportPackageIsVersion4

// WALServiceClient is the client API for WALService service.
//
// For semantics around ctx use and closing/ending streaming RPCs, please refer to https://godoc.org/google.golang.org/grpc#ClientConn.NewStream.
type WALServiceClient interface {
	GetMissingEntries(ctx context.Context, in *MissingEntriesRequest, opts ...grpc.CallOption) (*MissingEntriesResponse, error)
}

type wALServiceClient struct {
	cc *grpc.ClientConn
}

func NewWALServiceClient(cc *grpc.ClientConn) WALServiceClient {
	return &wALServiceClient{cc}
}

func (c *wALServiceClient) GetMissingEntries(ctx context.Context, in *MissingEntriesRequest, opts ...grpc.CallOption) (*MissingEntriesResponse, error) {
	out := new(MissingEntriesResponse)
	err := c.cc.Invoke(ctx, "/proto.WALService/GetMissingEntries", in, out, opts...)
	if err != nil {
		return nil, err
	}
	return out, nil
}

// WALServiceServer is the server API for WALService service.
type WALServiceServer interface {
	GetMissingEntries(context.Context, *MissingEntriesRequest) (*MissingEntriesResponse, error)
}

// UnimplementedWALServiceServer can be embedded to have forward compatible implementations.
type UnimplementedWALServiceServer struct {
}

func (*UnimplementedWALServiceServer) GetMissingEntries(ctx context.Context, req *MissingEntriesRequest) (*MissingEntriesResponse, error) {
	return nil, status.Errorf(codes.Unimplemented, "method GetMissingEntries not implemented")
}

func RegisterWALServiceServer(s *grpc.Server, srv WALServiceServer) {
	s.RegisterService(&_WALService_serviceDesc, srv)
}

func _WALService_GetMissingEntries_Handler(srv interface{}, ctx context.Context, dec func(interface{}) error, interceptor grpc.UnaryServerInterceptor) (interface{}, error) {
	in := new(MissingEntriesRequest)
	if err := dec(in); err != nil {
		return nil, err
	}
	if interceptor == nil {
		return srv.(WALServiceServer).GetMissingEntries(ctx, in)
	}
	info := &grpc.UnaryServerInfo{
		Server:     srv,
		FullMethod: "/proto.WALService/GetMissingEntries",
	}
	handler := func(ctx context.Context, req interface{}) (interface{}, error) {
		return srv.(WALServiceServer).GetMissingEntries(ctx, req.(*MissingEntriesRequest))
	}
	return interceptor(ctx, in, info, handler)
}

var _WALService_serviceDesc = grpc.ServiceDesc{
	ServiceName: "proto.WALService",
	HandlerType: (*WALServiceServer)(nil),
	Methods: []grpc.MethodDesc{
		{
			MethodName: "GetMissingEntries",
			Handler:    _WALService_GetMissingEntries_Handler,
		},
	},
	Streams:  []grpc.StreamDesc{},
	Metadata: "recover_wal.proto",
}

func (m *MissingEntriesRequest) Marshal() (dAtA []byte, err error) {
	size := m.Size()
	dAtA = make([]byte, size)
	n, err := m.MarshalToSizedBuffer(dAtA[:size])
	if err != nil {
		return nil, err
	}
	return dAtA[:n], nil
}

func (m *MissingEntriesRequest) MarshalTo(dAtA []byte) (int, error) {
	size := m.Size()
	return m.MarshalToSizedBuffer(dAtA[:size])
}

func (m *MissingEntriesRequest) MarshalToSizedBuffer(dAtA []byte) (int, error) {
	i := len(dAtA)
	_ = i
	var l int
	_ = l
	if len(m.Indexes) > 0 {
		dAtA2 := make([]byte, len(m.Indexes)*10)
		var j1 int
		for _, num := range m.Indexes {
			for num >= 1<<7 {
				dAtA2[j1] = uint8(uint64(num)&0x7f | 0x80)
				num >>= 7
				j1++
			}
			dAtA2[j1] = uint8(num)
			j1++
		}
		i -= j1
		copy(dAtA[i:], dAtA2[:j1])
		i = encodeVarintRecoverWal(dAtA, i, uint64(j1))
		i--
		dAtA[i] = 0xa
	}
	return len(dAtA) - i, nil
}

func (m *MissingEntriesResponse) Marshal() (dAtA []byte, err error) {
	size := m.Size()
	dAtA = make([]byte, size)
	n, err := m.MarshalToSizedBuffer(dAtA[:size])
	if err != nil {
		return nil, err
	}
	return dAtA[:n], nil
}

func (m *MissingEntriesResponse) MarshalTo(dAtA []byte) (int, error) {
	size := m.Size()
	return m.MarshalToSizedBuffer(dAtA[:size])
}

func (m *MissingEntriesResponse) MarshalToSizedBuffer(dAtA []byte) (int, error) {
	i := len(dAtA)
	_ = i
	var l int
	_ = l
	if len(m.Entries) > 0 {
		for iNdEx := len(m.Entries) - 1; iNdEx >= 0; iNdEx-- {
			{
				size, err := m.Entries[iNdEx].MarshalToSizedBuffer(dAtA[:i])
				if err != nil {
					return 0, err
				}
				i -= size
				i = encodeVarintRecoverWal(dAtA, i, uint64(size))
			}
			i--
			dAtA[i] = 0xa
		}
	}
	return len(dAtA) - i, nil
}

func (m *Entry) Marshal() (dAtA []byte, err error) {
	size := m.Size()
	dAtA = make([]byte, size)
	n, err := m.MarshalToSizedBuffer(dAtA[:size])
	if err != nil {
		return nil, err
	}
	return dAtA[:n], nil
}

func (m *Entry) MarshalTo(dAtA []byte) (int, error) {
	size := m.Size()
	return m.MarshalToSizedBuffer(dAtA[:size])
}

func (m *Entry) MarshalToSizedBuffer(dAtA []byte) (int, error) {
	i := len(dAtA)
	_ = i
	var l int
	_ = l
	if len(m.Data) > 0 {
		i -= len(m.Data)
		copy(dAtA[i:], m.Data)
		i = encodeVarintRecoverWal(dAtA, i, uint64(len(m.Data)))
		i--
		dAtA[i] = 0x1a
	}
	if m.Term != 0 {
		i = encodeVarintRecoverWal(dAtA, i, uint64(m.Term))
		i--
		dAtA[i] = 0x10
	}
	if m.Index != 0 {
		i = encodeVarintRecoverWal(dAtA, i, uint64(m.Index))
		i--
		dAtA[i] = 0x8
	}
	return len(dAtA) - i, nil
}

func encodeVarintRecoverWal(dAtA []byte, offset int, v uint64) int {
	offset -= sovRecoverWal(v)
	base := offset
	for v >= 1<<7 {
		dAtA[offset] = uint8(v&0x7f | 0x80)
		v >>= 7
		offset++
	}
	dAtA[offset] = uint8(v)
	return base
}
func (m *MissingEntriesRequest) Size() (n int) {
	if m == nil {
		return 0
	}
	var l int
	_ = l
	if len(m.Indexes) > 0 {
		l = 0
		for _, e := range m.Indexes {
			l += sovRecoverWal(uint64(e))
		}
		n += 1 + sovRecoverWal(uint64(l)) + l
	}
	return n
}

func (m *MissingEntriesResponse) Size() (n int) {
	if m == nil {
		return 0
	}
	var l int
	_ = l
	if len(m.Entries) > 0 {
		for _, e := range m.Entries {
			l = e.Size()
			n += 1 + l + sovRecoverWal(uint64(l))
		}
	}
	return n
}

func (m *Entry) Size() (n int) {
	if m == nil {
		return 0
	}
	var l int
	_ = l
	if m.Index != 0 {
		n += 1 + sovRecoverWal(uint64(m.Index))
	}
	if m.Term != 0 {
		n += 1 + sovRecoverWal(uint64(m.Term))
	}
	l = len(m.Data)
	if l > 0 {
		n += 1 + l + sovRecoverWal(uint64(l))
	}
	return n
}

func sovRecoverWal(x uint64) (n int) {
	return (math_bits.Len64(x|1) + 6) / 7
}
func sozRecoverWal(x uint64) (n int) {
	return sovRecoverWal(uint64((x << 1) ^ uint64((int64(x) >> 63))))
}
func (m *MissingEntriesRequest) Unmarshal(dAtA []byte) error {
	l := len(dAtA)
	iNdEx := 0
	for iNdEx < l {
		preIndex := iNdEx
		var wire uint64
		for shift := uint(0); ; shift += 7 {
			if shift >= 64 {
				return ErrIntOverflowRecoverWal
			}
			if iNdEx >= l {
				return io.ErrUnexpectedEOF
			}
			b := dAtA[iNdEx]
			iNdEx++
			wire |= uint64(b&0x7F) << shift
			if b < 0x80 {
				break
			}
		}
		fieldNum := int32(wire >> 3)
		wireType := int(wire & 0x7)
		if wireType == 4 {
			return fmt.Errorf("proto: MissingEntriesRequest: wiretype end group for non-group")
		}
		if fieldNum <= 0 {
			return fmt.Errorf("proto: MissingEntriesRequest: illegal tag %d (wire type %d)", fieldNum, wire)
		}
		switch fieldNum {
		case 1:
			if wireType == 0 {
				var v uint64
				for shift := uint(0); ; shift += 7 {
					if shift >= 64 {
						return ErrIntOverflowRecoverWal
					}
					if iNdEx >= l {
						return io.ErrUnexpectedEOF
					}
					b := dAtA[iNdEx]
					iNdEx++
					v |= uint64(b&0x7F) << shift
					if b < 0x80 {
						break
					}
				}
				m.Indexes = append(m.Indexes, v)
			} else if wireType == 2 {
				var packedLen int
				for shift := uint(0); ; shift += 7 {
					if shift >= 64 {
						return ErrIntOverflowRecoverWal
					}
					if iNdEx >= l {
						return io.ErrUnexpectedEOF
					}
					b := dAtA[iNdEx]
					iNdEx++
					packedLen |= int(b&0x7F) << shift
					if b < 0x80 {
						break
					}
				}
				if packedLen < 0 {
					return ErrInvalidLengthRecoverWal
				}
				postIndex := iNdEx + packedLen
				if postIndex < 0 {
					return ErrInvalidLengthRecoverWal
				}
				if postIndex > l {
					return io.ErrUnexpectedEOF
				}
				var elementCount int
				var count int
				for _, integer := range dAtA[iNdEx:postIndex] {
					if integer < 128 {
						count++
					}
				}
				elementCount = count
				if elementCount != 0 && len(m.Indexes) == 0 {
					m.Indexes = make([]uint64, 0, elementCount)
				}
				for iNdEx < postIndex {
					var v uint64
					for shift := uint(0); ; shift += 7 {
						if shift >= 64 {
							return ErrIntOverflowRecoverWal
						}
						if iNdEx >= l {
							return io.ErrUnexpectedEOF
						}
						b := dAtA[iNdEx]
						iNdEx++
						v |= uint64(b&0x7F) << shift
						if b < 0x80 {
							break
						}
					}
					m.Indexes = append(m.Indexes, v)
				}
			} else {
				return fmt.Errorf("proto: wrong wireType = %d for field Indexes", wireType)
			}
		default:
			iNdEx = preIndex
			skippy, err := skipRecoverWal(dAtA[iNdEx:])
			if err != nil {
				return err
			}
			if (skippy < 0) || (iNdEx+skippy) < 0 {
				return ErrInvalidLengthRecoverWal
			}
			if (iNdEx + skippy) > l {
				return io.ErrUnexpectedEOF
			}
			iNdEx += skippy
		}
	}

	if iNdEx > l {
		return io.ErrUnexpectedEOF
	}
	return nil
}
func (m *MissingEntriesResponse) Unmarshal(dAtA []byte) error {
	l := len(dAtA)
	iNdEx := 0
	for iNdEx < l {
		preIndex := iNdEx
		var wire uint64
		for shift := uint(0); ; shift += 7 {
			if shift >= 64 {
				return ErrIntOverflowRecoverWal
			}
			if iNdEx >= l {
				return io.ErrUnexpectedEOF
			}
			b := dAtA[iNdEx]
			iNdEx++
			wire |= uint64(b&0x7F) << shift
			if b < 0x80 {
				break
			}
		}
		fieldNum := int32(wire >> 3)
		wireType := int(wire & 0x7)
		if wireType == 4 {
			return fmt.Errorf("proto: MissingEntriesResponse: wiretype end group for non-group")
		}
		if fieldNum <= 0 {
			return fmt.Errorf("proto: MissingEntriesResponse: illegal tag %d (wire type %d)", fieldNum, wire)
		}
		switch fieldNum {
		case 1:
			if wireType != 2 {
				return fmt.Errorf("proto: wrong wireType = %d for field Entries", wireType)
			}
			var msglen int
			for shift := uint(0); ; shift += 7 {
				if shift >= 64 {
					return ErrIntOverflowRecoverWal
				}
				if iNdEx >= l {
					return io.ErrUnexpectedEOF
				}
				b := dAtA[iNdEx]
				iNdEx++
				msglen |= int(b&0x7F) << shift
				if b < 0x80 {
					break
				}
			}
			if msglen < 0 {
				return ErrInvalidLengthRecoverWal
			}
			postIndex := iNdEx + msglen
			if postIndex < 0 {
				return ErrInvalidLengthRecoverWal
			}
			if postIndex > l {
				return io.ErrUnexpectedEOF
			}
			m.Entries = append(m.Entries, &Entry{})
			if err := m.Entries[len(m.Entries)-1].Unmarshal(dAtA[iNdEx:postIndex]); err != nil {
				return err
			}
			iNdEx = postIndex
		default:
			iNdEx = preIndex
			skippy, err := skipRecoverWal(dAtA[iNdEx:])
			if err != nil {
				return err
			}
			if (skippy < 0) || (iNdEx+skippy) < 0 {
				return ErrInvalidLengthRecoverWal
			}
			if (iNdEx + skippy) > l {
				return io.ErrUnexpectedEOF
			}
			iNdEx += skippy
		}
	}

	if iNdEx > l {
		return io.ErrUnexpectedEOF
	}
	return nil
}
func (m *Entry) Unmarshal(dAtA []byte) error {
	l := len(dAtA)
	iNdEx := 0
	for iNdEx < l {
		preIndex := iNdEx
		var wire uint64
		for shift := uint(0); ; shift += 7 {
			if shift >= 64 {
				return ErrIntOverflowRecoverWal
			}
			if iNdEx >= l {
				return io.ErrUnexpectedEOF
			}
			b := dAtA[iNdEx]
			iNdEx++
			wire |= uint64(b&0x7F) << shift
			if b < 0x80 {
				break
			}
		}
		fieldNum := int32(wire >> 3)
		wireType := int(wire & 0x7)
		if wireType == 4 {
			return fmt.Errorf("proto: Entry: wiretype end group for non-group")
		}
		if fieldNum <= 0 {
			return fmt.Errorf("proto: Entry: illegal tag %d (wire type %d)", fieldNum, wire)
		}
		switch fieldNum {
		case 1:
			if wireType != 0 {
				return fmt.Errorf("proto: wrong wireType = %d for field Index", wireType)
			}
			m.Index = 0
			for shift := uint(0); ; shift += 7 {
				if shift >= 64 {
					return ErrIntOverflowRecoverWal
				}
				if iNdEx >= l {
					return io.ErrUnexpectedEOF
				}
				b := dAtA[iNdEx]
				iNdEx++
				m.Index |= uint64(b&0x7F) << shift
				if b < 0x80 {
					break
				}
			}
		case 2:
			if wireType != 0 {
				return fmt.Errorf("proto: wrong wireType = %d for field Term", wireType)
			}
			m.Term = 0
			for shift := uint(0); ; shift += 7 {
				if shift >= 64 {
					return ErrIntOverflowRecoverWal
				}
				if iNdEx >= l {
					return io.ErrUnexpectedEOF
				}
				b := dAtA[iNdEx]
				iNdEx++
				m.Term |= uint64(b&0x7F) << shift
				if b < 0x80 {
					break
				}
			}
		case 3:
			if wireType != 2 {
				return fmt.Errorf("proto: wrong wireType = %d for field Data", wireType)
			}
			var byteLen int
			for shift := uint(0); ; shift += 7 {
				if shift >= 64 {
					return ErrIntOverflowRecoverWal
				}
				if iNdEx >= l {
					return io.ErrUnexpectedEOF
				}
				b := dAtA[iNdEx]
				iNdEx++
				byteLen |= int(b&0x7F) << shift
				if b < 0x80 {
					break
				}
			}
			if byteLen < 0 {
				return ErrInvalidLengthRecoverWal
			}
			postIndex := iNdEx + byteLen
			if postIndex < 0 {
				return ErrInvalidLengthRecoverWal
			}
			if postIndex > l {
				return io.ErrUnexpectedEOF
			}
			m.Data = append(m.Data[:0], dAtA[iNdEx:postIndex]...)
			if m.Data == nil {
				m.Data = []byte{}
			}
			iNdEx = postIndex
		default:
			iNdEx = preIndex
			skippy, err := skipRecoverWal(dAtA[iNdEx:])
			if err != nil {
				return err
			}
			if (skippy < 0) || (iNdEx+skippy) < 0 {
				return ErrInvalidLengthRecoverWal
			}
			if (iNdEx + skippy) > l {
				return io.ErrUnexpectedEOF
			}
			iNdEx += skippy
		}
	}

	if iNdEx > l {
		return io.ErrUnexpectedEOF
	}
	return nil
}
func skipRecoverWal(dAtA []byte) (n int, err error) {
	l := len(dAtA)
	iNdEx := 0
	depth := 0
	for iNdEx < l {
		var wire uint64
		for shift := uint(0); ; shift += 7 {
			if shift >= 64 {
				return 0, ErrIntOverflowRecoverWal
			}
			if iNdEx >= l {
				return 0, io.ErrUnexpectedEOF
			}
			b := dAtA[iNdEx]
			iNdEx++
			wire |= (uint64(b) & 0x7F) << shift
			if b < 0x80 {
				break
			}
		}
		wireType := int(wire & 0x7)
		switch wireType {
		case 0:
			for shift := uint(0); ; shift += 7 {
				if shift >= 64 {
					return 0, ErrIntOverflowRecoverWal
				}
				if iNdEx >= l {
					return 0, io.ErrUnexpectedEOF
				}
				iNdEx++
				if dAtA[iNdEx-1] < 0x80 {
					break
				}
			}
		case 1:
			iNdEx += 8
		case 2:
			var length int
			for shift := uint(0); ; shift += 7 {
				if shift >= 64 {
					return 0, ErrIntOverflowRecoverWal
				}
				if iNdEx >= l {
					return 0, io.ErrUnexpectedEOF
				}
				b := dAtA[iNdEx]
				iNdEx++
				length |= (int(b) & 0x7F) << shift
				if b < 0x80 {
					break
				}
			}
			if length < 0 {
				return 0, ErrInvalidLengthRecoverWal
			}
			iNdEx += length
		case 3:
			depth++
		case 4:
			if depth == 0 {
				return 0, ErrUnexpectedEndOfGroupRecoverWal
			}
			depth--
		case 5:
			iNdEx += 4
		default:
			return 0, fmt.Errorf("proto: illegal wireType %d", wireType)
		}
		if iNdEx < 0 {
			return 0, ErrInvalidLengthRecoverWal
		}
		if depth == 0 {
			return iNdEx, nil
		}
	}
	return 0, io.ErrUnexpectedEOF
}

var (
	ErrInvalidLengthRecoverWal        = fmt.Errorf("proto: negative length found during unmarshaling")
	ErrIntOverflowRecoverWal          = fmt.Errorf("proto: integer overflow")
	ErrUnexpectedEndOfGroupRecoverWal = fmt.Errorf("proto: unexpected end of group")
)