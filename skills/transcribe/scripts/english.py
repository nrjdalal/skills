"""Is this transcript English? Function-word ratio -- no model, no network."""
import re

# closed-class English words. A speaker cannot produce fluent English without them,
# and romanised Hindi/other languages do not supply them.
FW = set("""the a an and or but if of to in on at for with from by as is are was were
be been being have has had do does did not no so that this these those it its he she
they we you i him her them my your our their there here what which who how when where
why can could will would should may might must about into over under after before
than then just like get got go going make made take see know think want need really""".split())

def english_ratio(text):
    toks = re.findall(r"[a-z']+", text.lower())
    if len(toks) < 50: return None, len(toks)
    return sum(t in FW for t in toks) / len(toks), len(toks)
