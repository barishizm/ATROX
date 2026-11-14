import { z } from "zod";

export const MAX_MESSAGE_LENGTH = 2000;

export const coachChatRequest = z.object({
  thread_id: z.string().uuid().optional(),
  message: z.string().trim().min(1).max(MAX_MESSAGE_LENGTH),
  locale: z.string().regex(/^[a-z]{2}(-[A-Za-z0-9]{2,8})?$/),
}).strict();

export type CoachChatRequest = z.infer<typeof coachChatRequest>;
