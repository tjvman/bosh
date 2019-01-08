// Code generated by protoc-gen-go. DO NOT EDIT.
// source: cpi.proto

package cpi

import (
	context "context"
	fmt "fmt"
	proto "github.com/golang/protobuf/proto"
	grpc "google.golang.org/grpc"
	math "math"
)

// Reference imports to suppress errors if they are not otherwise used.
var _ = proto.Marshal
var _ = fmt.Errorf
var _ = math.Inf

// This is a compile-time assertion to ensure that this generated file
// is compatible with the proto package it is being compiled against.
// A compilation error at this line likely means your copy of the
// proto package needs to be updated.
const _ = proto.ProtoPackageIsVersion3 // please upgrade the proto package

type Request struct {
	Type                 string   `protobuf:"bytes,1,opt,name=type,proto3" json:"type,omitempty"`
	StemcellApiVersion   int32    `protobuf:"varint,2,opt,name=stemcell_api_version,json=stemcellApiVersion,proto3" json:"stemcell_api_version,omitempty"`
	DirectorUuid         string   `protobuf:"bytes,3,opt,name=director_uuid,json=directorUuid,proto3" json:"director_uuid,omitempty"`
	Properties           []byte   `protobuf:"bytes,4,opt,name=properties,proto3" json:"properties,omitempty"`
	XXX_NoUnkeyedLiteral struct{} `json:"-"`
	XXX_unrecognized     []byte   `json:"-"`
	XXX_sizecache        int32    `json:"-"`
}

func (m *Request) Reset()         { *m = Request{} }
func (m *Request) String() string { return proto.CompactTextString(m) }
func (*Request) ProtoMessage()    {}
func (*Request) Descriptor() ([]byte, []int) {
	return fileDescriptor_27dcbb49f4ec00bf, []int{0}
}

func (m *Request) XXX_Unmarshal(b []byte) error {
	return xxx_messageInfo_Request.Unmarshal(m, b)
}
func (m *Request) XXX_Marshal(b []byte, deterministic bool) ([]byte, error) {
	return xxx_messageInfo_Request.Marshal(b, m, deterministic)
}
func (m *Request) XXX_Merge(src proto.Message) {
	xxx_messageInfo_Request.Merge(m, src)
}
func (m *Request) XXX_Size() int {
	return xxx_messageInfo_Request.Size(m)
}
func (m *Request) XXX_DiscardUnknown() {
	xxx_messageInfo_Request.DiscardUnknown(m)
}

var xxx_messageInfo_Request proto.InternalMessageInfo

func (m *Request) GetType() string {
	if m != nil {
		return m.Type
	}
	return ""
}

func (m *Request) GetStemcellApiVersion() int32 {
	if m != nil {
		return m.StemcellApiVersion
	}
	return 0
}

func (m *Request) GetDirectorUuid() string {
	if m != nil {
		return m.DirectorUuid
	}
	return ""
}

func (m *Request) GetProperties() []byte {
	if m != nil {
		return m.Properties
	}
	return nil
}

type Response struct {
	Error     *Response_Error `protobuf:"bytes,1,opt,name=error,proto3" json:"error,omitempty"`
	RequestId string          `protobuf:"bytes,2,opt,name=request_id,json=requestId,proto3" json:"request_id,omitempty"`
	Log       string          `protobuf:"bytes,3,opt,name=log,proto3" json:"log,omitempty"`
	// Types that are valid to be assigned to Result:
	//	*Response_InfoResult
	//	*Response_TestResult
	Result               isResponse_Result `protobuf_oneof:"result"`
	XXX_NoUnkeyedLiteral struct{}          `json:"-"`
	XXX_unrecognized     []byte            `json:"-"`
	XXX_sizecache        int32             `json:"-"`
}

func (m *Response) Reset()         { *m = Response{} }
func (m *Response) String() string { return proto.CompactTextString(m) }
func (*Response) ProtoMessage()    {}
func (*Response) Descriptor() ([]byte, []int) {
	return fileDescriptor_27dcbb49f4ec00bf, []int{1}
}

func (m *Response) XXX_Unmarshal(b []byte) error {
	return xxx_messageInfo_Response.Unmarshal(m, b)
}
func (m *Response) XXX_Marshal(b []byte, deterministic bool) ([]byte, error) {
	return xxx_messageInfo_Response.Marshal(b, m, deterministic)
}
func (m *Response) XXX_Merge(src proto.Message) {
	xxx_messageInfo_Response.Merge(m, src)
}
func (m *Response) XXX_Size() int {
	return xxx_messageInfo_Response.Size(m)
}
func (m *Response) XXX_DiscardUnknown() {
	xxx_messageInfo_Response.DiscardUnknown(m)
}

var xxx_messageInfo_Response proto.InternalMessageInfo

func (m *Response) GetError() *Response_Error {
	if m != nil {
		return m.Error
	}
	return nil
}

func (m *Response) GetRequestId() string {
	if m != nil {
		return m.RequestId
	}
	return ""
}

func (m *Response) GetLog() string {
	if m != nil {
		return m.Log
	}
	return ""
}

type isResponse_Result interface {
	isResponse_Result()
}

type Response_InfoResult struct {
	InfoResult *InfoResult `protobuf:"bytes,5,opt,name=info_result,json=infoResult,proto3,oneof"`
}

type Response_TestResult struct {
	TestResult *TestResult `protobuf:"bytes,6,opt,name=test_result,json=testResult,proto3,oneof"`
}

func (*Response_InfoResult) isResponse_Result() {}

func (*Response_TestResult) isResponse_Result() {}

func (m *Response) GetResult() isResponse_Result {
	if m != nil {
		return m.Result
	}
	return nil
}

func (m *Response) GetInfoResult() *InfoResult {
	if x, ok := m.GetResult().(*Response_InfoResult); ok {
		return x.InfoResult
	}
	return nil
}

func (m *Response) GetTestResult() *TestResult {
	if x, ok := m.GetResult().(*Response_TestResult); ok {
		return x.TestResult
	}
	return nil
}

// XXX_OneofWrappers is for the internal use of the proto package.
func (*Response) XXX_OneofWrappers() []interface{} {
	return []interface{}{
		(*Response_InfoResult)(nil),
		(*Response_TestResult)(nil),
	}
}

type Response_Error struct {
	Type                 string   `protobuf:"bytes,1,opt,name=type,proto3" json:"type,omitempty"`
	Message              string   `protobuf:"bytes,2,opt,name=message,proto3" json:"message,omitempty"`
	OkToRetry            bool     `protobuf:"varint,3,opt,name=ok_to_retry,json=okToRetry,proto3" json:"ok_to_retry,omitempty"`
	XXX_NoUnkeyedLiteral struct{} `json:"-"`
	XXX_unrecognized     []byte   `json:"-"`
	XXX_sizecache        int32    `json:"-"`
}

func (m *Response_Error) Reset()         { *m = Response_Error{} }
func (m *Response_Error) String() string { return proto.CompactTextString(m) }
func (*Response_Error) ProtoMessage()    {}
func (*Response_Error) Descriptor() ([]byte, []int) {
	return fileDescriptor_27dcbb49f4ec00bf, []int{1, 0}
}

func (m *Response_Error) XXX_Unmarshal(b []byte) error {
	return xxx_messageInfo_Response_Error.Unmarshal(m, b)
}
func (m *Response_Error) XXX_Marshal(b []byte, deterministic bool) ([]byte, error) {
	return xxx_messageInfo_Response_Error.Marshal(b, m, deterministic)
}
func (m *Response_Error) XXX_Merge(src proto.Message) {
	xxx_messageInfo_Response_Error.Merge(m, src)
}
func (m *Response_Error) XXX_Size() int {
	return xxx_messageInfo_Response_Error.Size(m)
}
func (m *Response_Error) XXX_DiscardUnknown() {
	xxx_messageInfo_Response_Error.DiscardUnknown(m)
}

var xxx_messageInfo_Response_Error proto.InternalMessageInfo

func (m *Response_Error) GetType() string {
	if m != nil {
		return m.Type
	}
	return ""
}

func (m *Response_Error) GetMessage() string {
	if m != nil {
		return m.Message
	}
	return ""
}

func (m *Response_Error) GetOkToRetry() bool {
	if m != nil {
		return m.OkToRetry
	}
	return false
}

type InfoResult struct {
	ApiVersion           int32    `protobuf:"varint,1,opt,name=api_version,json=apiVersion,proto3" json:"api_version,omitempty"`
	StemcellFormats      []string `protobuf:"bytes,2,rep,name=stemcell_formats,json=stemcellFormats,proto3" json:"stemcell_formats,omitempty"`
	XXX_NoUnkeyedLiteral struct{} `json:"-"`
	XXX_unrecognized     []byte   `json:"-"`
	XXX_sizecache        int32    `json:"-"`
}

func (m *InfoResult) Reset()         { *m = InfoResult{} }
func (m *InfoResult) String() string { return proto.CompactTextString(m) }
func (*InfoResult) ProtoMessage()    {}
func (*InfoResult) Descriptor() ([]byte, []int) {
	return fileDescriptor_27dcbb49f4ec00bf, []int{2}
}

func (m *InfoResult) XXX_Unmarshal(b []byte) error {
	return xxx_messageInfo_InfoResult.Unmarshal(m, b)
}
func (m *InfoResult) XXX_Marshal(b []byte, deterministic bool) ([]byte, error) {
	return xxx_messageInfo_InfoResult.Marshal(b, m, deterministic)
}
func (m *InfoResult) XXX_Merge(src proto.Message) {
	xxx_messageInfo_InfoResult.Merge(m, src)
}
func (m *InfoResult) XXX_Size() int {
	return xxx_messageInfo_InfoResult.Size(m)
}
func (m *InfoResult) XXX_DiscardUnknown() {
	xxx_messageInfo_InfoResult.DiscardUnknown(m)
}

var xxx_messageInfo_InfoResult proto.InternalMessageInfo

func (m *InfoResult) GetApiVersion() int32 {
	if m != nil {
		return m.ApiVersion
	}
	return 0
}

func (m *InfoResult) GetStemcellFormats() []string {
	if m != nil {
		return m.StemcellFormats
	}
	return nil
}

type TestResult struct {
	Potato               string   `protobuf:"bytes,1,opt,name=potato,proto3" json:"potato,omitempty"`
	XXX_NoUnkeyedLiteral struct{} `json:"-"`
	XXX_unrecognized     []byte   `json:"-"`
	XXX_sizecache        int32    `json:"-"`
}

func (m *TestResult) Reset()         { *m = TestResult{} }
func (m *TestResult) String() string { return proto.CompactTextString(m) }
func (*TestResult) ProtoMessage()    {}
func (*TestResult) Descriptor() ([]byte, []int) {
	return fileDescriptor_27dcbb49f4ec00bf, []int{3}
}

func (m *TestResult) XXX_Unmarshal(b []byte) error {
	return xxx_messageInfo_TestResult.Unmarshal(m, b)
}
func (m *TestResult) XXX_Marshal(b []byte, deterministic bool) ([]byte, error) {
	return xxx_messageInfo_TestResult.Marshal(b, m, deterministic)
}
func (m *TestResult) XXX_Merge(src proto.Message) {
	xxx_messageInfo_TestResult.Merge(m, src)
}
func (m *TestResult) XXX_Size() int {
	return xxx_messageInfo_TestResult.Size(m)
}
func (m *TestResult) XXX_DiscardUnknown() {
	xxx_messageInfo_TestResult.DiscardUnknown(m)
}

var xxx_messageInfo_TestResult proto.InternalMessageInfo

func (m *TestResult) GetPotato() string {
	if m != nil {
		return m.Potato
	}
	return ""
}

func init() {
	proto.RegisterType((*Request)(nil), "cpi.Request")
	proto.RegisterType((*Response)(nil), "cpi.Response")
	proto.RegisterType((*Response_Error)(nil), "cpi.Response.Error")
	proto.RegisterType((*InfoResult)(nil), "cpi.InfoResult")
	proto.RegisterType((*TestResult)(nil), "cpi.TestResult")
}

func init() { proto.RegisterFile("cpi.proto", fileDescriptor_27dcbb49f4ec00bf) }

var fileDescriptor_27dcbb49f4ec00bf = []byte{
	// 397 bytes of a gzipped FileDescriptorProto
	0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0xff, 0x6c, 0x92, 0xc1, 0x6e, 0xd3, 0x40,
	0x10, 0x86, 0x71, 0x9c, 0xa4, 0xf1, 0x24, 0x55, 0xab, 0x01, 0x21, 0xab, 0x12, 0xc5, 0x72, 0x39,
	0xb8, 0x1c, 0x22, 0x14, 0x9e, 0x00, 0x10, 0x88, 0xdc, 0xd0, 0xaa, 0x45, 0xdc, 0x2c, 0x63, 0x4f,
	0xaa, 0x55, 0x1d, 0xcf, 0xb2, 0xbb, 0x46, 0xca, 0x7b, 0xf0, 0x1e, 0xbc, 0x22, 0xda, 0xb5, 0x1d,
	0x07, 0xa9, 0xb7, 0x9d, 0x7f, 0x3c, 0x9e, 0xef, 0xdf, 0x7f, 0x21, 0x2a, 0x95, 0x5c, 0x2b, 0xcd,
	0x96, 0x31, 0x2c, 0x95, 0x4c, 0xff, 0x04, 0x70, 0x26, 0xe8, 0x57, 0x4b, 0xc6, 0x22, 0xc2, 0xd4,
	0x1e, 0x14, 0xc5, 0x41, 0x12, 0x64, 0x91, 0xf0, 0x67, 0x7c, 0x07, 0x2f, 0x8c, 0xa5, 0x7d, 0x49,
	0x75, 0x9d, 0x17, 0x4a, 0xe6, 0xbf, 0x49, 0x1b, 0xc9, 0x4d, 0x3c, 0x49, 0x82, 0x6c, 0x26, 0x70,
	0xe8, 0x7d, 0x50, 0xf2, 0x7b, 0xd7, 0xc1, 0x1b, 0x38, 0xaf, 0xa4, 0xa6, 0xd2, 0xb2, 0xce, 0xdb,
	0x56, 0x56, 0x71, 0xe8, 0x7f, 0xb7, 0x1a, 0xc4, 0xfb, 0x56, 0x56, 0x78, 0x0d, 0xa0, 0x34, 0x2b,
	0xd2, 0x56, 0x92, 0x89, 0xa7, 0x49, 0x90, 0xad, 0xc4, 0x89, 0x92, 0xfe, 0x9d, 0xc0, 0x42, 0x90,
	0x51, 0xdc, 0x18, 0xc2, 0x5b, 0x98, 0x91, 0xd6, 0xac, 0x3d, 0xd8, 0x72, 0xf3, 0x7c, 0xed, 0x3c,
	0x0c, 0xdd, 0xf5, 0x67, 0xd7, 0x12, 0xdd, 0x17, 0xf8, 0x0a, 0x40, 0x77, 0x6e, 0x72, 0x59, 0x79,
	0xc8, 0x48, 0x44, 0xbd, 0xb2, 0xad, 0xf0, 0x12, 0xc2, 0x9a, 0x1f, 0x7a, 0x22, 0x77, 0xc4, 0x0d,
	0x2c, 0x65, 0xb3, 0xe3, 0x5c, 0x93, 0x69, 0x6b, 0x1b, 0xcf, 0xfc, 0x86, 0x0b, 0xbf, 0x61, 0xdb,
	0xec, 0x58, 0x78, 0xf9, 0xeb, 0x33, 0x01, 0xf2, 0x58, 0xb9, 0x19, 0xeb, 0x36, 0xf4, 0x33, 0xf3,
	0x93, 0x99, 0x3b, 0x32, 0x76, 0x9c, 0xb1, 0xc7, 0xea, 0xea, 0x1e, 0x66, 0x1e, 0xf4, 0xc9, 0x4b,
	0x8e, 0xe1, 0x6c, 0x4f, 0xc6, 0x14, 0x0f, 0xd4, 0x23, 0x0f, 0x25, 0x5e, 0xc3, 0x92, 0x1f, 0x73,
	0xeb, 0xf8, 0xac, 0x3e, 0x78, 0xf0, 0x85, 0x88, 0xf8, 0xf1, 0x8e, 0x85, 0x13, 0x3e, 0x2e, 0x60,
	0xde, 0x51, 0xa4, 0x3f, 0x00, 0x46, 0x60, 0x7c, 0x0d, 0xcb, 0xd3, 0xb4, 0x02, 0x9f, 0x16, 0x14,
	0x63, 0x4a, 0xb7, 0x70, 0x79, 0xcc, 0x75, 0xc7, 0x7a, 0x5f, 0x58, 0x13, 0x4f, 0x92, 0x30, 0x8b,
	0xc4, 0xc5, 0xa0, 0x7f, 0xe9, 0xe4, 0xf4, 0x0d, 0xc0, 0x68, 0x0b, 0x5f, 0xc2, 0x5c, 0xb1, 0x2d,
	0x2c, 0xf7, 0x0e, 0xfa, 0x6a, 0xf3, 0x16, 0xc2, 0x4f, 0xdf, 0xb6, 0x78, 0x03, 0x53, 0x87, 0x81,
	0xab, 0x3e, 0x24, 0x7f, 0xf3, 0x57, 0xe7, 0xff, 0x45, 0xf6, 0x73, 0xee, 0x1f, 0xe0, 0xfb, 0x7f,
	0x01, 0x00, 0x00, 0xff, 0xff, 0x36, 0x55, 0x00, 0xfe, 0x8d, 0x02, 0x00, 0x00,
}

// Reference imports to suppress errors if they are not otherwise used.
var _ context.Context
var _ grpc.ClientConn

// This is a compile-time assertion to ensure that this generated file
// is compatible with the grpc package it is being compiled against.
const _ = grpc.SupportPackageIsVersion4

// CPIClient is the client API for CPI service.
//
// For semantics around ctx use and closing/ending streaming RPCs, please refer to https://godoc.org/google.golang.org/grpc#ClientConn.NewStream.
type CPIClient interface {
	Info(ctx context.Context, in *Request, opts ...grpc.CallOption) (*Response, error)
}

type cPIClient struct {
	cc *grpc.ClientConn
}

func NewCPIClient(cc *grpc.ClientConn) CPIClient {
	return &cPIClient{cc}
}

func (c *cPIClient) Info(ctx context.Context, in *Request, opts ...grpc.CallOption) (*Response, error) {
	out := new(Response)
	err := c.cc.Invoke(ctx, "/cpi.CPI/Info", in, out, opts...)
	if err != nil {
		return nil, err
	}
	return out, nil
}

// CPIServer is the server API for CPI service.
type CPIServer interface {
	Info(context.Context, *Request) (*Response, error)
}

func RegisterCPIServer(s *grpc.Server, srv CPIServer) {
	s.RegisterService(&_CPI_serviceDesc, srv)
}

func _CPI_Info_Handler(srv interface{}, ctx context.Context, dec func(interface{}) error, interceptor grpc.UnaryServerInterceptor) (interface{}, error) {
	in := new(Request)
	if err := dec(in); err != nil {
		return nil, err
	}
	if interceptor == nil {
		return srv.(CPIServer).Info(ctx, in)
	}
	info := &grpc.UnaryServerInfo{
		Server:     srv,
		FullMethod: "/cpi.CPI/Info",
	}
	handler := func(ctx context.Context, req interface{}) (interface{}, error) {
		return srv.(CPIServer).Info(ctx, req.(*Request))
	}
	return interceptor(ctx, in, info, handler)
}

var _CPI_serviceDesc = grpc.ServiceDesc{
	ServiceName: "cpi.CPI",
	HandlerType: (*CPIServer)(nil),
	Methods: []grpc.MethodDesc{
		{
			MethodName: "Info",
			Handler:    _CPI_Info_Handler,
		},
	},
	Streams:  []grpc.StreamDesc{},
	Metadata: "cpi.proto",
}
