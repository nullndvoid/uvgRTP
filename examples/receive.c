#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

#include <uvgrtp/wrapper_c.h>

char REMOTE_ADDRESS[] = "127.0.0.1";
uint16_t REMOTE_PORT = 8891; // sender local port
uint16_t LOCAL_PORT = 8890;  // receiver local port

int AMOUNT_OF_TEST_PACKETS = 100;

int main(void)
{
    printf("Starting uvgRTP RTP receiving example.\n");

    uvgrtp_context ctx = uvgrtp_create_ctx();
    if (!ctx)
        return EXIT_FAILURE;

    uvgrtp_session sess = uvgrtp_create_session(ctx, REMOTE_ADDRESS);
    if (!sess)
        return EXIT_FAILURE;

    int flags = RCE_RECEIVE_ONLY;
    uvgrtp_stream opus = uvgrtp_create_stream(sess, LOCAL_PORT, REMOTE_PORT, RTP_FORMAT_OPUS, flags);
    if (!opus)
        return EXIT_FAILURE;

    int received = 0;
    while (received < AMOUNT_OF_TEST_PACKETS)
    {
        uvgrtp_frame *frame = uvgrtp_pull_frame(opus);
        if (!frame)
        {
            printf("uvgrtp_pull_frame failed (rtp_errno=%d)\n", rtp_errno);
            continue;
        }

        ++received;
        printf("Received frame %d/%d, payload_len=%zu\n",
               received, AMOUNT_OF_TEST_PACKETS, frame->payload_len);

        /* If your wrapper uses a different free function name, replace this call accordingly. */
        uvgrtp_frame_free(frame);
    }

    uvgrtp_destroy_stream(sess, opus);
    uvgrtp_destroy_session(ctx, sess);
    uvgrtp_destroy_ctx(ctx);

    return EXIT_SUCCESS;
}