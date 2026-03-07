#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

#include <uvgrtp/wrapper_c.h>

/* RTP is a protocol for real-time streaming. The simplest usage
 * scenario is sending one RTP stream and receiving it. This example
 * Shows how to send one RTP stream. These examples perform a simple
 * test if they are run. You may run the receiving examples at the same
 * time to see the whole demo. */

char REMOTE_ADDRESS[] = "127.0.0.1";
uint16_t REMOTE_PORT = 8890;
uint16_t LOCAL_PORT = 8891;

// the parameters of demostration
size_t PAYLOAD_LEN = 100;
int AMOUNT_OF_TEST_PACKETS = 100;

int main(void)
{
    printf("Starting uvgRTP RTP sending example.\n");

    uvgrtp_context ctx = uvgrtp_create_ctx();
    if (!ctx)
        return EXIT_FAILURE;

    uvgrtp_session sess = uvgrtp_create_session(ctx, REMOTE_ADDRESS);
    if (!sess)
        return EXIT_FAILURE;

    int flags = RCE_SEND_ONLY;
    uvgrtp_stream opus = uvgrtp_create_stream(sess, LOCAL_PORT, REMOTE_PORT, RTP_FORMAT_OPUS, flags);
    if (!opus)
        return EXIT_FAILURE;

    uint8_t *dummy_frame = (uint8_t *)malloc(PAYLOAD_LEN);
    if (!dummy_frame)
        return EXIT_FAILURE;

    for (int i = 0; i < AMOUNT_OF_TEST_PACKETS; ++i)
    {
        memset(dummy_frame, 'a', PAYLOAD_LEN);

        if ((i + 1) % 10 == 0 || i == 0)
            printf("Sending frame %d/%d\n", i + 1, AMOUNT_OF_TEST_PACKETS);

        if (uvgrtp_push_frame(opus, dummy_frame, PAYLOAD_LEN, RTP_NO_FLAGS) != RTP_OK)
            printf("Failed to send RTP frame (rtp_errno=%d)\n", rtp_errno);
    }

    free(dummy_frame);

    uvgrtp_destroy_stream(sess, opus);
    uvgrtp_destroy_session(ctx, sess);
    uvgrtp_destroy_ctx(ctx);

    return EXIT_SUCCESS;
}