package modelproc

import "time"

// SetTimeAfterForTest replaces the time.After implementation for testing retry delays.
// Only available in test builds.
func (p *ModelProcessor) SetTimeAfterForTest(f func(time.Duration) <-chan time.Time) {
	p.timeAfter = f
}
