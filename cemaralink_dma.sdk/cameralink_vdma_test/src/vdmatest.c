#include "xparameters.h"
#include "xil_io.h"
#include "xil_printf.h"
#include "xil_cache.h"
#include "xaxivdma.h"
#include "xstatus.h"
#include "sleep.h"
#include <string.h>
#include "xaxivdma_hw.h"

#define XAXIVDMA_S2MM_OFFSET  0x30
#define VDMA_SR_HALTED        (1U << 0)

/* Hardware IDs */
#define DEC_BASEADDR      XPAR_CAMERALINK_DECODER_A_0_S00_AXI_BASEADDR
#define VDMA_DEVICE_ID    XPAR_AXIVDMA_0_DEVICE_ID

/* Image parameters */
#define FRAME_WIDTH       1280U
#define FRAME_HEIGHT      1024U
#define BYTES_PER_PIXEL   1U

#define HSIZE_BYTES       (FRAME_WIDTH * BYTES_PER_PIXEL)
#define STRIDE_BYTES      (FRAME_WIDTH * BYTES_PER_PIXEL)
#define FRAME_SIZE        (STRIDE_BYTES * FRAME_HEIGHT)

/* Frame buffers */
#define FRAME_BUF_BASE    0x10000000U
#define FRAME_BUF_0       (FRAME_BUF_BASE)
#define FRAME_BUF_1       (FRAME_BUF_BASE + FRAME_SIZE)
#define FRAME_BUF_2       (FRAME_BUF_BASE + FRAME_SIZE * 2U)

/* Decoder register offsets */
#define DEC_REG_CONTROL   0x00U
#define DEC_REG_STATUS    0x04U
#define DEC_REG_WIDTH     0x08U
#define DEC_REG_HEIGHT    0x0CU

/* CONTROL bit definitions */
#define CTRL_ENABLE       (1U << 0)
#define CTRL_SOFT_RESET   (1U << 1)
#define CTRL_CLEAR_STATUS (1U << 2)

/* Decoder STATUS bit definitions */
#define STATUS_FIFO_FULL  (1U << 0)
#define STATUS_AXIS_VALID (1U << 1)
#define STATUS_ERROR      (1U << 2)

/* VDMA driver instance */
static XAxiVdma AxiVdma;

/*
 * Shadow value of CONTROL register.
 * Modify individual bits without accidentally
 * overwriting other control bits.
 */
static u32 DecControlShadow = 0U;

static inline void Dec_Write(u32 Offset, u32 Value)
{
    Xil_Out32(DEC_BASEADDR + Offset, Value);
}

static inline u32 Dec_Read(u32 Offset)
{
    return Xil_In32(DEC_BASEADDR + Offset);
}

static void Decoder_WriteControl(void)
{
    Dec_Write(DEC_REG_CONTROL, DecControlShadow);
}

static void Decoder_Enable(void)
{
    DecControlShadow |= CTRL_ENABLE;
    Decoder_WriteControl();
}

static void Decoder_Disable(void)
{
    DecControlShadow &= ~CTRL_ENABLE;
    Decoder_WriteControl();
}

static void Decoder_SoftReset(void)
{
    /* Step 1: bit[1]=0 -> enter reset */
    DecControlShadow &= ~CTRL_SOFT_RESET;
    Decoder_WriteControl();
    usleep(1000);

    /* Step 2: bit[1]=1 -> release reset, FIFO works */
    DecControlShadow |= CTRL_SOFT_RESET;
    Decoder_WriteControl();
    usleep(1000);
}

static void Decoder_ClearStatus(void)
{
    DecControlShadow |= CTRL_CLEAR_STATUS;
    Decoder_WriteControl();

    usleep(10);

    DecControlShadow &= ~CTRL_CLEAR_STATUS;
    Decoder_WriteControl();
}

static void Decoder_PrintStatus(void)
{
    u32 Status;

    Status = Dec_Read(DEC_REG_STATUS);

    xil_printf("DEC_STATUS = 0x%08x\r\n", Status);
    xil_printf("  fifo_full  = %d\r\n",
               (Status & STATUS_FIFO_FULL) ? 1 : 0);
    xil_printf("  axis_valid = %d\r\n",
               (Status & STATUS_AXIS_VALID) ? 1 : 0);
    xil_printf("  error      = %d\r\n",
               (Status & STATUS_ERROR) ? 1 : 0);
}

static int SetupVdmaWrite(void)
{
    XAxiVdma_Config *Config;
    XAxiVdma_DmaSetup WriteCfg;
    UINTPTR FrameAddr[3];
    int Status;

    xil_printf("Lookup VDMA config...\r\n");

    Config = XAxiVdma_LookupConfig(VDMA_DEVICE_ID);

    if (Config == NULL) {
        xil_printf("ERROR: VDMA config not found\r\n");
        return XST_FAILURE;
    }

    xil_printf("VDMA base address = 0x%08x\r\n",
               Config->BaseAddress);

    xil_printf("Initialize VDMA driver...\r\n");

    Status = XAxiVdma_CfgInitialize(
        &AxiVdma,
        Config,
        Config->BaseAddress
    );

    if (Status != XST_SUCCESS) {
        xil_printf("ERROR: XAxiVdma_CfgInitialize failed, %d\r\n",
                   Status);
        return XST_FAILURE;
    }

    /* Zero the entire config structure */
    memset(&WriteCfg, 0, sizeof(WriteCfg));

    /* 2D image transfer parameters */
    WriteCfg.VertSizeInput = FRAME_HEIGHT;
    WriteCfg.HoriSizeInput = HSIZE_BYTES;
    WriteCfg.Stride = STRIDE_BYTES;

    WriteCfg.FrameDelay = 0;
    WriteCfg.EnableCircularBuf = 1;
    WriteCfg.EnableSync = 0;
    WriteCfg.PointNum = 0;
    WriteCfg.EnableFrameCounter = 0;
    WriteCfg.FixedFrameStoreAddr = 0;

    xil_printf("Configure VDMA S2MM...\r\n");

    Status = XAxiVdma_DmaConfig(
        &AxiVdma,
        XAXIVDMA_WRITE,
        &WriteCfg
    );

    if (Status != XST_SUCCESS) {
        xil_printf("ERROR: XAxiVdma_DmaConfig failed, %d\r\n",
                   Status);
        return XST_FAILURE;
    }
    /* 确保 RESET 位被清除（DmaStart 有时不会自动清） */
    {
        u32 Cr = Xil_In32(AxiVdma.BaseAddr + XAXIVDMA_S2MM_OFFSET);
        if (Cr & 0x2) {
            xil_printf("WARNING: S2MM RESET bit stuck, clearing...\r\n");
            Xil_Out32(AxiVdma.BaseAddr + XAXIVDMA_S2MM_OFFSET, Cr & ~0x2U);
        }
    }

    FrameAddr[0] = FRAME_BUF_0;
    FrameAddr[1] = FRAME_BUF_1;
    FrameAddr[2] = FRAME_BUF_2;

    xil_printf("Set frame buffer addresses...\r\n");

    Status = XAxiVdma_DmaSetBufferAddr(
        &AxiVdma,
        XAXIVDMA_WRITE,
        FrameAddr
    );

    if (Status != XST_SUCCESS) {
        xil_printf("ERROR: XAxiVdma_DmaSetBufferAddr failed, %d\r\n",
                   Status);
        return XST_FAILURE;
    }

    xil_printf("Start VDMA S2MM...\r\n");

    Status = XAxiVdma_DmaStart(
        &AxiVdma,
        XAXIVDMA_WRITE
    );

    if (Status != XST_SUCCESS) {
        xil_printf("ERROR: XAxiVdma_DmaStart failed, %d\r\n",
                   Status);
        return XST_FAILURE;
    }

    xil_printf("VDMA S2MM started successfully\r\n");

    return XST_SUCCESS;
}

/*
 * Poll VDMA S2MM status register until Halted=0.
 * Halted=0 means RS has taken effect and the channel
 * is out of stop state. tready is ready at this point.
 */
static int WaitForVdmaS2MMReady(u32 VdmaBaseAddr, u32 TimeoutMs)
{
    u32 S2MMBase = VdmaBaseAddr + XAXIVDMA_S2MM_OFFSET;
    u32 Ctrl, Sr;

    Ctrl = Xil_In32(S2MMBase);
    Sr   = Xil_In32(S2MMBase + 0x04);

    xil_printf("VDMA S2MM CR=0x%08x, SR=0x%08x\r\n", Ctrl, Sr);

    while (TimeoutMs > 0) {
        Sr = Xil_In32(S2MMBase + 0x04);

        /* Halted=0: RS acknowledged, channel active, tready ready */
        if (!(Sr & VDMA_SR_HALTED)) {
            xil_printf("VDMA ready (Halted=0), SR=0x%08x\r\n", Sr);
            return XST_SUCCESS;
        }

        usleep(1000);
        TimeoutMs--;
    }

    xil_printf("ERROR: timeout, final SR=0x%08x\r\n", Sr);
    return XST_FAILURE;
}

int main(void)
{
    int Status;
    u32 DecStatus, VdmaErrors;

    xil_printf("\r\n");
    xil_printf("==== Stage 4: Decoder + VDMA Link Test ====\r\n");

    /* 1. Init decoder (reset released, but not enabled) */
    DecControlShadow = 0U;
    Decoder_WriteControl();
    Decoder_SoftReset();        // bit[1]=1, bit[0]=0
    Decoder_ClearStatus();

    DecStatus = Dec_Read(DEC_REG_STATUS);
    xil_printf("1. Decoder ready, STATUS=0x%08x\r\n", DecStatus);

    /* 2. Start VDMA first (let it wait for tuser/SOF) */
    xil_printf("2. Starting VDMA...\r\n");
    Status = SetupVdmaWrite();
    if (Status != XST_SUCCESS) {
        xil_printf("FATAL: VDMA setup failed\r\n");
        while (1);
    }

    VdmaErrors = XAxiVdma_GetDmaChannelErrors(&AxiVdma, XAXIVDMA_WRITE);
    xil_printf("   VDMA errors = 0x%08x\r\n", VdmaErrors);

    /* 3. Wait for VDMA hardware to exit Halted state */
    Status = WaitForVdmaS2MMReady(AxiVdma.BaseAddr, 5000);
    if (Status != XST_SUCCESS) {
        xil_printf("FATAL: VDMA not ready\r\n");
        while (1);
    }

    /* 4. Enable decoder last */
    xil_printf("4. Enable decoder\r\n");
    memset((void *)FRAME_BUF_0, 0xAA, FRAME_SIZE);
    memset((void *)FRAME_BUF_1, 0xAA, FRAME_SIZE);
    memset((void *)FRAME_BUF_2, 0xAA, FRAME_SIZE);
    Decoder_Enable();

    /* 5. Wait for data to flow */
    sleep(2);
    volatile u8 *p = (volatile u8 *)FRAME_BUF_0;
       int i, changed = 0;
       for (i = 0; i < 64; i++) {
           if (p[i] != 0xAA) changed = 1;
       }
       xil_printf("Frame 0 first 64 bytes: ");
       for (i = 0; i < 64; i++) xil_printf("%02x ", p[i]);
       xil_printf("\r\n");
       xil_printf("Data changed: %s\r\n", changed ? "YES" : "NO");

    /* 6. Check status */
    xil_printf("5. Status after 2 seconds:\r\n");
    DecStatus = Dec_Read(DEC_REG_STATUS);
    xil_printf("   DEC STATUS = 0x%08x\r\n", DecStatus);
    xil_printf("   fifo_full  = %d (expect 0 - VDMA is consuming)\r\n",
               (DecStatus & STATUS_FIFO_FULL) ? 1 : 0);
    xil_printf("   axis_valid = %d (expect 1 - data flowing)\r\n",
               (DecStatus & STATUS_AXIS_VALID) ? 1 : 0);
    xil_printf("   error      = %d (expect 0)\r\n",
               (DecStatus & STATUS_ERROR) ? 1 : 0);

    VdmaErrors = XAxiVdma_GetDmaChannelErrors(&AxiVdma, XAXIVDMA_WRITE);
    xil_printf("   VDMA errors = 0x%08x\r\n", VdmaErrors);

    /* 7. Monitor loop */
    while (1) {
        DecStatus = Dec_Read(DEC_REG_STATUS);
        VdmaErrors = XAxiVdma_GetDmaChannelErrors(&AxiVdma, XAXIVDMA_WRITE);

        xil_printf("DEC=0x%08x VDMA_ERR=0x%08x\r\n", DecStatus, VdmaErrors);

        if (DecStatus & STATUS_ERROR) {
            xil_printf("Decoder error! Clearing...\r\n");
            Decoder_ClearStatus();
        }//应该设置一个tick标记，计数错误然后再清除

        sleep(1);
    }

    return 0;
}
